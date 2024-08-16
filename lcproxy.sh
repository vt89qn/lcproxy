proxy_count=$1;

# Check validity of user provided arguments
re='^[0-9]+$'
if ! [[ $proxy_count =~ $re ]] ; then
	echo "please passing proxy count, ex : 'bash lcproxy.sh 200' ";
	exit 1;
fi;
  
#iptables -I INPUT -p tcp --match multiport --dport 30000:35000 -m state --state NEW -j ACCEPT
function install_proxy() {
	( # Install proxy server
	  wget https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz &> /dev/null
	  tar -xf 0.9.4.tar.gz
	  rm -f 0.9.4.tar.gz
	  mv -f 3proxy-0.9.4 3proxy)
	# Build proxy server
	cd 3proxy
	make -f Makefile.Linux;
	cd ~
}

function stop_proxy(){
	local pid="$(pidof 3proxy/bin/3proxy 3proxy/cfg/3proxy.cfg)";
	echo "$pid";
	if [ -z "$pid" ]; then echo "not running"; else echo "running -> kill"; kill $pid; fi;
}

function start_proxy(){
	3proxy/bin/3proxy 3proxy/cfg/3proxy.cfg &
}

function rotate(){
	interface_name="$(ip -br l | awk '$1 !~ "lo|vir|wl|@NONE" { print $1 }' | awk 'NR==1')";
	main_ip6="$( ip -6 addr show dev $interface_name | grep -Po '(?<=inet6\s)(?!fe80).+(?=/64\sscope\s.+\snoprefixroute)' )";
	main_ip4="$( ip -4 addr show dev $interface_name | grep -Po '(?<=inet\s).+(?=/\d+.+\sscope\s.+\snoprefixroute)' )";
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
	for(( i=0; i<$1; i++ ));do
		new_ip="$prefix_ip:$(rh)$(rh)$(rh)$(rh):$(rh)$(rh)$(rh)$(rh):$(rh)$(rh)$(rh)$(rh):$(rh)$(rh)$(rh)$(rh)";
		new_ips+=($new_ip);
		new_ips_cfg+=("proxy -6 -n -a -p$((30000+$i)) -i$main_ip4 -e$new_ip");
		ip -6 addr add $new_ip/64 dev $interface_name;
	done;
	
	printf -v new_ips_cfg_string '%s\n' "${new_ips_cfg[@]}";
	#echo "${new_ips_cfg_string%,}";
	
	echo "nserver 1.1.1.1
maxconn 200
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
auth none
${new_ips_cfg_string%,}">3proxy/cfg/3proxy.cfg;

	for old_ip in "${old_ips[@]}";do ip -6 addr del $old_ip/64 dev $interface_name; done;
	
	stop_proxy;
	start_proxy;
}

if [ ! -d "3proxy" ]; then
	echo 'install_proxy'; 
	yum update -y;
	install_proxy ; 
	firewall-cmd --zone=public --add-port=30000-31000/tcp --permanent;
	firewall-cmd --reload;
fi

echo 'rotate'; 
rotate $proxy_count;

#curl -sO https://raw.githubusercontent.com/vt89qn/lcproxy/main/lcproxy.sh && chmod +x lcproxy.sh 
#bash lcproxy.sh -act i
#bash lcproxy.sh -act r -count 200

#firewall-cmd --zone=public --add-port=30000-31000/tcp --permanent
#firewall-cmd --reload
