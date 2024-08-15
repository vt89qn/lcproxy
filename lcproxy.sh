act = ""
while true; do
  case "$1" in
    -act ) act="$2"; shift 2 ;;
    -count ) proxy_count="$2"; shift 2 ;;
    -- ) shift; break ;;
    * ) break ;;
  esac
done


#iptables -I INPUT -p tcp --match multiport --dport 30000:35000 -m state --state NEW -j ACCEPT

function install_3proxy() {
	cd ~
	echo -e "\nDownloading proxy server source...";
	( # Install proxy server
	  wget https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz &> /dev/null
	  tar -xf 0.9.4.tar.gz
	  rm -f 0.9.4.tar.gz
	  mv 3proxy-0.9.4 3proxy)
	echo "Proxy server source code downloaded successfully";

	echo -e "\nStart building proxy server execution file from source...";
	# Build proxy server
	cd 3proxy
	make -f Makefile.Linux;
	if test -f "3proxy/bin/3proxy"; then
		echo "Proxy server builded successfully"
	else
		echo "Error: proxy server build from source code failed."
	fi;
	cd ~
}

if [ "$act" = "i" ]; then 
	echo 'install_3proxy'; 
	install_3proxy ; 
elif [ "$act" = "r" ]; then 
	echo 'rotate'; 
else 
	echo 'do nothing'; 
fi;
