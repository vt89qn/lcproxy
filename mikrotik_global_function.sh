{
    :global getIp4PPPoE do={:return ([/interface pppoe-client monitor $1 as-value once]->"local-address");}
    
    :global getNextNatDstPort do={
        :local nextDstPort [/system/clock/get time];
        :set nextDstPort ([:pick $nextDstPort 0 2]*1000 + [:pick $nextDstPort 3 5]*100 + [:pick $nextDstPort 6 8]);
        :local isOK false ;
        :while (!$isOK) do={
            :if ([/ip/firewall/nat/find dst-port=$nextDstPort] = "") do={:set isOK true;} else={
                :set nextDstPort ($nextDstPort + 100);
                :if ($nextDstPort > 60000) do={
                    :set nextDstPort ($nextDstPort % 10000 + 5000);
                }
            }
        }
        :return $nextDstPort;
    }
    
    :global changeIp do={
        :local pppoeClientName $1;
        :if ($pppoeClientName ~ "ether\\d+_PPPoEClent_\\d+") do={
            :local etherIndex [:pick $pppoeClientName 5 [:find $pppoeClientName "_"]];
            :local pppIndex [:pick $pppoeClientName ([:find $pppoeClientName "_"]+12) [:len $pppoeClientName]];
            :local oldIp [$getIp4PPPoE $pppoeClientName];
            :put ("oldIp  =$oldIp");
            :local newIp "";
            :local isChanged false;
            :local i 1 ;
            :local isOK false ;
            :while (!$isOK and $i <= 5) do={
                :set i ($i + 1);
                /interface/pppoe-client/disable [find name=$pppoeClientName];
                delay 5s ;
                /interface/pppoe-client/enable [find name=$pppoeClientName];
                
                #doi ip moi
                :local j 1 ;
                :while (!$isOK and $j <= 5) do={
                    :set j ($j+ 1);
                    delay 2s;
                    :set newIp [$getIp4PPPoE $1];
                    :put ("newIp  =$newIp");
                    :if ($newIp != "" and $newIp != $oldIp) do={:set isOK true;}
                }
            }
            :if ($isOK) do={
                :local natToAddress ("100.10.$etherIndex.$pppIndex");
                :local checkId [/ip/firewall/nat/find to-addresses=$natToAddress] ;
                :local natDstPort [$getNextNatDstPort];
                :if ( $checkId = "") do={
                    :put "add NAT";
                    /ip/firewall/nat/add          dst-address=$newIp dst-port=$natDstPort to-ports=3128 comment=("proxy $pppoeClientName") protocol=tcp to-addresses=$natToAddress action=dst-nat chain=dstnat dst-address-type=local;
                } else={
                    :put "update NAT";
                    /ip/firewall/nat/set $checkId dst-address=$newIp dst-port=$natDstPort to-ports=3128;
                }
            } else={:put ("changeIP fail old $oldIp -> new $newIp");}
        } else={:put ("PPPoE client name $pppoeClientName is invalid");}
    }
}
