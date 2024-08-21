#script cài box 1
{
   #đồng bộ thời gian
   /system/clock/set time-zone-autodetect=no time-zone-name=Asia/Ho_Chi_Minh ;
   /system/ntp/client/set enabled=yes ;
   /system/ntp/client/servers/add address=vn.pool.ntp.org ;
   #cho phép all ppp kết nối internet
   /ip/firewall/nat/add chain=srcnat action=masquerade out-interface=all-ppp ;
}
#script cài box 2
{
   #chọn cổng làm việc
   :local etherIndex 1 ;
   :local etherName ("ether".$etherIndex) ;
   :local checkId "" ;
   #tạo bridge BridgeLAN
   /interface/bridge/add name=($etherName."_BridgeLAN") ;
   #thêm cổng ether6 vào BridgeLAN
   /interface/bridge/port/add bridge=($etherName."_BridgeLAN") interface=ether6 ;
   #thêm ip cho BridgeLAN
   /ip/address/add address=("192.168.0.1/24") interface=($etherName."_BridgeLAN") network=("192.168.0.0") ;
   #thêm PPPoE client
   /interface/pppoe-client/add add-default-route=yes comment="$etherName PPPoE Client" disabled=no interface=$etherName name=($etherName."_PPPoEClent") user=t008_gftth_phuongvt398 password=89JAKA ;
   #DHCP Server
   /ip/pool/add name=($etherName."_BridgeLAN_IpPool") ranges=192.168.0.10-192.168.0.20 ;
   /ip/dhcp-server/add address-pool=($etherName."_BridgeLAN_IpPool") interface=($etherName."_BridgeLAN") lease-time=1d name=($etherName."_BridgeLAN_DHCP") ; 
   /ip/dhcp-server/network/add address=192.168.0.0/24 gateway=192.168.0.1 ;
   /ip/dns/set servers=8.8.8.8,8.8.4.4 ;
}
