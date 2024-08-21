{
   #chọn cổng làm việc
   :local etherIndex 1 ;
   :local etherName ("ether".$etherIndex) ;
   :local checkId "" ;
   #tạo bridge BridgeContainer
   :set checkId [/interface/bridge/find name=($etherName."_BridgeContainer")] ;
   :if ( $checkId = "" ) do={
      :put "add Bridge $etherName_BridgeContainer" ;
      /interface/bridge/add name=($etherName."_BridgeContainer") ;
   } else={
      :put "exist Bridge $etherName_BridgeContainer" ;
   }
   #thêm ip cho BridgeContainer
   :set checkId [/ip/address/find interface=($etherName."_BridgeContainer")] ;
   :if ( $checkId = "" ) do={
      :put "add IP Address $etherName_BridgeContainer" ;
      /ip/address/add address=("100.10.".$etherIndex.".253/24") interface=($etherName."_BridgeContainer") network=("100.10.".$etherIndex.".0") ;
	  
   } else={
      :put "update IP Address $etherName_BridgeContainer" ;
	  /ip/address/set $checkId address=("100.10.".$etherIndex.".253/24") network=("100.10.".$etherIndex.".0") ;
   }
   
   #thêm proxy
   :for i from=1 to=29 do={
      :put "proxy $i" ;
	  
	  :set checkId [/interface/macvlan/find name=($etherName."_MACVLAN_".$i)] ;
      :if ( $checkId = "") do={
		 :put "add MACVLAN $etherName_MACVLAN_$i" ;
		 /interface/macvlan/add interface=$etherName name=($etherName."_MACVLAN_".$i) mode=private ;
      } else={
	     :put "exist MACVLAN $etherName_MACVLAN_$i" ;
	     #/interface/macvlan/set $checkId interface=$etherName mode=private ;
	  }
	  
	  :set checkId [/interface/pppoe-client/find name=($etherName."_PPPoEClent_".$i)] ;
      :if ( $checkId = "") do={
	     :put "add PPPoE Client $etherName_PPPoEClent_$i" ;
	     /interface/pppoe-client/add copy-from=($etherName."_PPPoEClent") interface=($etherName."_MACVLAN_".$i) name=($etherName."_PPPoEClent_".$i) add-default-route=no use-peer-dns=no disabled=yes ;
      } else={
	     :put "exist PPPoE Client $etherName_PPPoEClent_$i" ;
	  }
	  
	  :set checkId [/routing/table/find name=($etherName."_RoutingTable_".$i)] ;
      :if ( $checkId = "") do={
	     :put "add Routing Tables $etherName_RoutingTable_$i" ;
		 /routing/table/add fib name=($etherName."_RoutingTable_".$i) ;
      } else={
	     :put "exist Routing Tables $etherName_RoutingTable_$i" ;
	  }

	  :set checkId [/ip/firewall/mangle/find new-routing-mark=($etherName."_RoutingTable_".$i)] ;
      :if ( $checkId = "") do={
	     :log warning message="add IP Firewall Mangle" ;
		 /ip/firewall/mangle/add action=mark-routing chain=prerouting new-routing-mark=($etherName."_RoutingTable_".$i) src-address=("100.10.".$etherIndex.".".$i) dst-address-list=!Local ;
      } else={
	     :put "update IP Firewall Mangle" ;
		 /ip/firewall/mangle/set $checkId action=mark-routing chain=prerouting src-address=("100.10.".$etherIndex.".".$i) dst-address-list=!Local ;
	  }

	  :set checkId [/ip/route/find routing-table=($etherName."_RoutingTable_".$i)] ;
      :if ( $checkId = "") do={
	     :put "add IP Route" ;
		 /ip/route/add dst-address=0.0.0.0/0 gateway=($etherName."_PPPoEClent_".$i) routing-table=($etherName."_RoutingTable_".$i) distance=1 scope=30 target-scope=10 ;
      } else={
	     :put "exist IP Route" ;
	  }
	  
      :set checkId [/interface/veth/find name=($etherName."_VETH_".$i)] ;
      :if ( $checkId = "") do={
         :put "add VETH $etherName_VETH_$i" ;
         /interface/veth/add name=($etherName."_VETH_".$i) address=("100.10.".$etherIndex.".".$i."/24") gateway=("100.10.".$etherIndex.".253") ;

      } else={
	     :put "update VETH $etherName_VETH_$i" ;
         /interface/veth/set $checkId address=("100.10.".$etherIndex.".".$i."/24") gateway=("100.10.".$etherIndex.".253") ;
	  }
	  
	  :set checkId [/interface/bridge/port/find interface=($etherName."_VETH_".$i)] ;
      :if ( $checkId = "") do={
         :put "add Port VETH $etherName_VETH_$i to Bridge $etherName_BridgeContainer"
         /interface/bridge/port/add bridge=($etherName."_BridgeContainer") interface=($etherName."_VETH_".$i) ;
      } else={
         :put "exist Port VETH $etherName_VETH_$i to Bridge $etherName_BridgeContainer" ;
         #/interface/bridge/port/set $checkId bridge=($etherName."_BridgeContainer") ;
	  }
	  
	  :set checkId [/container/find interface=($etherName."_VETH_".$i)] ;
      :if ( $checkId = "") do={
	     :put "add $etherName_Container_$i" ;
		 /container add comment=($etherName."_Container_".$i) file="proxy-amd64-v1.9.1.tar" interface=($etherName."_VETH_".$i) root-dir=("/Container/proxy/".$etherName."-container-".$i."-root") start-on-boot=yes ;
      } else={
	     :put "exist $etherName_Container_$i" ;
	  }
   }
}
