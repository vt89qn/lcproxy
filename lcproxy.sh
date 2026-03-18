BASE_PORT=""
PROXY_COUNT=""
AUTH_ARG=""
IP_ALLOW_ARG=""

while [ $# -gt 0 ]; do
    case "$1" in
        -port) BASE_PORT="$2"; shift 2 ;;
        -count) PROXY_COUNT="$2"; shift 2 ;;
        -auth) AUTH_ARG="$2"; shift 2 ;;
        -ip-allow) IP_ALLOW_ARG="$2"; shift 2 ;;
        *) shift ;;
    esac
done
  
#iptables -I INPUT -p tcp --match multiport --dport 30000:35000 -m state --state NEW -j ACCEPT
function install_proxy() {
	#yum -y install gcc wget
	( # Install proxy server
	  wget https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz &> /dev/null
	  tar -xf 0.9.4.tar.gz
	  rm -f 0.9.4.tar.gz
	  mv -f 3proxy-0.9.4 3proxy)
	# Build proxy server
	cd 3proxy
	make -f Makefile.Linux &>/dev/null;
	cd ~
}

function start_proxy(){
	local pid="$(pidof 3proxy/bin/3proxy 3proxy/cfg/3proxy.cfg)";
	if [ -z "$pid" ]; then 
		echo "not running -> start"; 
	else 
		echo "running -> reload";
		kill $pid;
	fi;
	3proxy/bin/3proxy 3proxy/cfg/3proxy.cfg &
}

function rotate(){
	interface_name="$(ip -br l | awk '$1 !~ "lo|vir|wl|@NONE" { print $1 }' | awk 'NR==1')";
	main_ip6="$( ip -6 addr show dev $interface_name | grep -Po '(?<=inet6\s)(?!fe80).+(?=/64\sscope\s.+\snoprefixroute)' )";
	#main_ip4="$( ip -4 addr show dev $interface_name | grep -Po '(?<=inet\s).+(?=/\d+.+\sscope\s.+\snoprefixroute)' )";
	#echo "$1";

	readarray -t old_ips < <( ip -6 addr show dev $interface_name | grep -Po '(?<=inet6\s).+(?=/64\sscope\sglobal)' );
	old_ips=("${old_ips[@]/$main_ip6}");
	#printf '%s\n' "${old_ips[@]}";
	#for ip in "${old_ips[@]}";do echo "$ip" ;done;
	
	prefix_ip="$( echo "$main_ip6" | cut -f1-4 -d':' )";
	#echo "$prefix_ip";
	
	new_ips=();
	new_ips_cfg=();
	array=( 1 2 3 4 5 6 7 8 9 0 a b c d e f );
	function rh () { echo "${array[$RANDOM%16]}"; }
	for(( i=0; i<$PROXY_COUNT; i++ ));do
		new_ip="$prefix_ip:$(rh)$(rh)$(rh)$(rh):$(rh)$(rh)$(rh)$(rh):$(rh)$(rh)$(rh)$(rh):$(rh)$(rh)$(rh)$(rh)";
		new_ips+=($new_ip);
		new_ips_cfg+=("proxy -6 -n -a -p$((BASE_PORT+i)) -e$new_ip");
		ip -6 addr add $new_ip/64 dev $interface_name;
	done;
	
	printf -v new_ips_cfg_string '%s\n' "${new_ips_cfg[@]}";
	#echo "${new_ips_cfg_string%,}";
	
	if [ -n "$AUTH_ARG" ] || [ -n "$IP_ALLOW_ARG" ]; then
		auth="auth"
		if [ -n "$IP_ALLOW_ARG" ]; then
			auth+=" iponly"
		fi
		if [ -n "$AUTH_ARG" ]; then
			auth+=" strong"
		fi
		if [ -n "$IP_ALLOW_ARG" ]; then
			auth+="
allow * ${IP_ALLOW_ARG}"
		fi
		if [ -n "$AUTH_ARG" ]; then
			PROXY_USER="$(echo "$AUTH_ARG" | cut -d: -f1)"
            PROXY_PASS="$(echo "$AUTH_ARG" | cut -d: -f2)"
			auth="users ${PROXY_USER}:CL:${PROXY_PASS}
${auth}
allow ${PROXY_USER}"
		fi
		auth+="
deny *"
	else
		auth="auth none"
	fi
	
	echo "daemon
nserver 1.1.1.1
nserver 8.8.8.8
maxconn 200
nscache 65536
timeouts 1 5 30 60 180 1800 15 60

${auth}

${new_ips_cfg_string%,}">3proxy/cfg/3proxy.cfg;

	ulimit -n 600000;
	ulimit -u 600000;
	
	for old_ip in "${old_ips[@]}";do ip -6 addr del $old_ip/64 dev $interface_name; done;
	
	echo "start_proxy";
	start_proxy;
}

if [ ! -d "3proxy" ]; then
	echo 'install_proxy'; 
	yum update -y;
	install_proxy ; 
	firewall-cmd --zone=public --add-port=30000-31000/tcp --permanent;
 	firewall-cmd --zone=public --add-port=80/tcp --permanent;
	firewall-cmd --reload;
fi

echo 'rotate'; 
rotate;

#curl -sO https://raw.githubusercontent.com/vt89qn/lcproxy/main/lcproxy.sh && chmod +x lcproxy.sh 
#bash lcproxy.sh -port 30100 -count 100 -auth user_name:pass_word -ip-allow 66.42.53.27
