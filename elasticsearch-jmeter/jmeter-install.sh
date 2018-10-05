#!/bin/bash

# The MIT License (MIT)
#
# Copyright (c) 2015 Microsoft Azure
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Hans Krijger (MSFT)
#

help()
{
    echo "This script installs JMeter on Ubuntu"
    echo "Parameters:"
    echo "  -h              view this help content"
    echo "  -m              install as a master node"
    echo "  -r <hosts>      set remote hosts (master only)"
    echo "  -t <testpack>   location of the test pack to download and unzip (master only)"
}

log()
{
    echo "$1"
}

error()
{
    echo "$1" >&2
    exit 1
}

if [ "${UID}" -ne 0 ];
then
    error "Script executed without root permissions"
fi

# script parameters
IS_MASTER=0
REMOTE_HOSTS=""
CLUSTER_NAME="elasticsearch"

while getopts :hmr:j:t: optname; do
  log "Option $optname set with value ${OPTARG}"
  case $optname in
    h) # show help
      help
      exit 2
      ;;
    m) # setup as master
      IS_MASTER=1
      ;;
    r) # provide remote hosts
      REMOTE_RANGE=${OPTARG}
      ;;
    t) # provide testpack
      TESTPACK=${OPTARG}
      ;;
    \?) # unrecognized option - show help
      help
      error "Option ${OPTARG} not allowed."
      ;;
  esac
done

expand_ip_range() {
    IFS='-' read -a HOST_IPS <<< "$1"
    declare -a MY_IPS=`ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'`
    declare -a EXPAND_STATICIP_RANGE_RESULTS=()
    for (( n=0 ; n<("${HOST_IPS[1]}"+0) ; n++))
    do
        HOST="${HOST_IPS[0]}${n}"
        if ! [[ "${MY_IPS[@]}" =~ "${HOST}" ]]; then
            EXPAND_STATICIP_RANGE_RESULTS+=($HOST)
        fi
    done
    echo "${EXPAND_STATICIP_RANGE_RESULTS[@]}"
}

install_java()
{
    log "Installing Java"
    add-apt-repository -y ppa:webupd8team/java
    mkdir -p /var/cache/oracle-jdk8-installer
    wget -q http://ftp.osuosl.org/pub/funtoo/distfiles/oracle-java/jdk-8u144-linux-x64.tar.gz -O /var/cache/oracle-jdk8-installer/jdk-8u144-linux-x64.tar.gz
    apt-get -y update
    echo debconf shared/accepted-oracle-license-v1-1 select true | sudo debconf-set-selections
    echo debconf shared/accepted-oracle-license-v1-1 seen true | sudo debconf-set-selections
    apt-get -y install oracle-java8-installer
}

install_jmeter_service()
{
    cat << EOF > /etc/init/jmeter.conf
    description "JMeter Service"

    start on starting
    script
        JVM_ARGS="-Xms1024m -Xmx6144m -XX:NewSize=512m -XX:MaxNewSize=6144m" && export JVM_ARGS && /opt/jmeter/apache-jmeter-4.0/bin/jmeter-server
    end script
EOF

    chmod +x /etc/init/jmeter.conf
    service jmeter start
}

update_config_sub()
{
    mv /opt/jmeter/apache-jmeter-4.0/bin/jmeter.properties /opt/jmeter/apache-jmeter-4.0/bin/jmeter.properties.bak
    cat /opt/jmeter/apache-jmeter-4.0/bin/jmeter.properties.bak | sed "s|#client.rmi.localport=0|client.rmi.localport=4441|" | sed "s|#server.rmi.localport=4000|server.rmi.localport=4440|" > /opt/jmeter/apache-jmeter-4.0/bin/jmeter.properties 
}

update_config_boss()
{
    mv /opt/jmeter/apache-jmeter-4.0/bin/jmeter.properties /opt/jmeter/apache-jmeter-4.0/bin/jmeter.properties.bak
    cat /opt/jmeter/apache-jmeter-4.0/bin/jmeter.properties.bak | sed "s|#client.rmi.localport=0|client.rmi.localport=4440|" | sed "s|remote_hosts=127.0.0.1|remote_hosts=${REMOTE_HOSTS}|" > /opt/jmeter/apache-jmeter-4.0/bin/jmeter.properties 
}

install_jmeter()
{
    log "Installing JMeter"
    apt-get -y install unzip 
    
    mkdir -p /opt/jmeter
    wget -O jmeter.zip https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-4.0.zip
    wget -O JMeterPlugins-Standard-1.4.0.zip http://jmeter-plugins.org/downloads/file/JMeterPlugins-Standard-1.4.0.zip
	wget -O JMeterPlugins-WebDriver-1.4.0.zip http://jmeter-plugins.org/downloads/file/JMeterPlugins-WebDriver-1.4.0.zip
	wget -O JMeterPlugins-ExtrasLibs-1.4.0.zip https://jmeter-plugins.org/downloads/file/JMeterPlugins-ExtrasLibs-1.4.0.zip
    
    log "unzipping jmeter"
    unzip -q jmeter.zip -d /opt/jmeter/
    
    log "unzipping plugins"
    unzip -q JMeterPlugins-Standard-1.4.0.zip -d /opt/jmeter/apache-jmeter-4.0/
	unzip -q JMeterPlugins-WebDriver-1.4.0.zip -d /opt/jmeter/apache-jmeter-4.0/
	unzip -q JMeterPlugins-ExtrasLibs-1.4.0.zip -d /opt/jmeter/apache-jmeter-4.0/
     
    chmod u+x /opt/jmeter/apache-jmeter-4.0/bin/jmeter-server
    chmod u+x /opt/jmeter/apache-jmeter-4.0/bin/jmeter

    
    if [ ${IS_MASTER} -ne 1 ]; 
    then
        log "setting up sub node"
        iptables -A INPUT -m state --state NEW -m tcp -p tcp --dport 4441 -j ACCEPT
        
        update_config_sub
        install_jmeter_service
    else
        log "setting up boss node"
        iptables -A INPUT -p tcp --match multiport --dports 4440:4445 -j ACCEPT
        iptables -A OUTPUT -p tcp --match multiport --dports 4440:4445 -j ACCEPT
    
        update_config_boss
        
        if [ ${TESTPACK} ];
        then
            log "installing test pack"
            wget -O testpack.zip ${TESTPACK}
            unzip -q testpack.zip -d /opt/jmeter/
            cp /opt/jmeter/testpack/* /opt/jmeter/
            rm -r /opt/jmeter/testpack/
            chmod +x /opt/jmeter/run.sh
        fi
    fi
    
    groupadd -g 999 jmeter
    useradd -u 999 -g 999 jmeter
    chown -R jmeter: /opt/jmeter
}
install_chromedriver()
{
    log "Installing chromedriver"
    apt-get -y update  > /dev/null
    apt-get -qy install wget default-jre-headless telnet iputils-ping unzip nodejs-legacy npm  > /dev/null
	npm install -g chromedriver > /dev/null
}


if [ ${REMOTE_RANGE} ];
then
    S=$(expand_ip_range "$REMOTE_RANGE")
    REMOTE_HOSTS="${S// /,}"
    log "using remote hosts ${REMOTE_HOSTS}"
fi

install_java
install_chromedriver
install_jmeter

log "script complete"
