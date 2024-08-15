act=""
while true; do
  case "$1" in
    -act ) act="$2"; shift 2 ;;
    -count ) proxy_count="$2"; shift 2 ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done


#iptables -I INPUT -p tcp --match multiport --dport 30000:35000 -m state --state NEW -j ACCEPT
function install() {
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
	local main_ip6="$(ip -6 addr show dev eth0 scope global | grep -Po '(?<=inet6\s).+(?=/64\sscope\sglobal\snoprefixroute)')";
	local main_ip4="$(ip -4 addr show dev eth0 scope global | grep -Po '(?<=inet\s).+(?=/24.+\sscope\sglobal\snoprefixroute)')";
	#echo "$1";

	readarray -t old_ips < <( ip -6 addr | grep -Po '(?<=inet6\s).+(?=/64\sscope\sglobal)');
	old_ips=("${old_ips[@]/$main_ip6}");
	#printf '%s\n' "${old_ips[@]}";
	#for ip in "${old_ips[@]}";do echo "$ip" ;done;
	
	prefix_ip="$(echo "$main_ip6" | cut -f1-4 -d':')";
	#echo "$prefix_ip";
	
	local new_ips=();
	local new_ips_cfg=();
	array=( 1 2 3 4 5 6 7 8 9 0 a b c d e f );
	function rh () { echo "${array[$RANDOM%16]}"; }
	for(( i=0; i<$1; i++ ));do
		new_ip="$prefix_ip:$(rh)$(rh)$(rh)$(rh):$(rh)$(rh)$(rh)$(rh):$(rh)$(rh)$(rh)$(rh):$(rh)$(rh)$(rh)$(rh)";
		new_ips+=($new_ip);
		new_ips_cfg+=("proxy -6 -n -a -p$((30000+$i)) -i$main_ip4 -e$new_ip");
		ip -6 addr add ${new_ip}/64 dev eth0;
	done;
	
	printf -v new_ips_cfg_string '%s\n' "${new_ips_cfg[@]}";
	#echo "${new_ips_cfg_string%,}";
	
	echo "nserver 1.1.1.1
maxconn 200
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
auth none
${new_ips_cfg_string%,}">3proxy/cfg/3proxy.cfg;

	for old_ip in "${old_ips[@]}";do ip -6 addr del $old_ip/64 dev eth0; done;
	
	stop_proxy;
	start_proxy;
}

if [ "$act" = "i" ]; then 
	echo 'install_3proxy'; 
	install_3proxy ; 
elif [ "$act" = "r" ]; then 
	echo 'rotate'; 
	rotate $proxy_count;
else 
	echo 'do nothing'; 
fi;
