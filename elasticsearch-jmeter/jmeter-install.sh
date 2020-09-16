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
    sudo apt update --assume-yes
    sudo apt install default-jre --assume-yes
}

create_jmeter_startup_script()
{
    cat << EOF > /opt/jmeter/start-jmeter-server.sh
    #!/bin/bash
    JVM_ARGS="-Xms1024m -Xmx6144m -XX:NewSize=512m -XX:MaxNewSize=6144m" && export JVM_ARGS && /opt/jmeter/apache-jmeter-5.0/bin/jmeter-server -DChrome_Driver=$(which chromedriver) -Djava.rmi.server.hostname=`ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1'`
EOF

   chmod +x /opt/jmeter/start-jmeter-server.sh
}

setup_jmeter_service()
{   
    cat << EOF > /etc/systemd/system/jmeter.service
    [Unit]
    Description=JMeter Service

    [Service]
    ExecStart=/opt/jmeter/start-jmeter-server.sh

    [Install]
    WantedBy=multi-user.target
EOF

    sudo systemctl start jmeter
    sudo systemctl enable jmeter
}

update_config_sub()
{
    export LANGUAGE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    export LC_TYPE=en_US.UTF-8
    wget -O /opt/jmeter/apache-jmeter-5.0/bin/rmi_keystore.jks https://github.com/axelavensia/jmeter-public/raw/master/elasticsearch-jmeter/resources/rmi_keystore.jks
    wget -O /opt/jmeter/apache-jmeter-5.0/bin/user.properties https://github.com/axelavensia/jmeter-public/raw/master/elasticsearch-jmeter/resources/user.properties
    mv /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties.bak
    #cat /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties.bak | sed "s|#server.rmi.ssl.disable=false|server.rmi.ssl.disable=true|" > /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties 
    #cat /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties.bak | sed "s|#server.rmi.ssl.disable=false|server.rmi.ssl.disable=false|" | sed "s|#client.rmi.localport=0|client.rmi.localport=4440|" | sed "s|#server.rmi.localport=4000|server.rmi.localport=4441|" | sed "s|#server.rmi.ssl.keystore.type=JKS|server.rmi.ssl.keystore.type=JKS|" | sed "s|#server.rmi.ssl.keystore.file=rmi_keystore.jks|server.rmi.ssl.keystore.file=/opt/jmeter/apache-jmeter-5.0/bin/rmi_keystore.jks|" | sed "s|#server.rmi.ssl.keystore.password=changeit|server.rmi.ssl.keystore.password=changeit|" | sed "s|#server.rmi.ssl.keystore.alias=rmi|server.rmi.ssl.keystore.alias=rmi|" > /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties

    cat /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties.bak > /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties


    #| sed "s|#server.rmi.ssl.keystore.type=JKS|server.rmi.ssl.keystore.type=JKS|" | sed "s|#server.rmi.ssl.keystore.file=rmi_keystore.jks|server.rmi.ssl.keystore.file=/opt/jmeter/apache-jmeter-5.0/bin/rmi_keystore.jks|" | sed "s|#server.rmi.ssl.keystore.password=changeit|server.rmi.ssl.keystore.password=changeit|" | sed "s|#server.rmi.ssl.keystore.alias=rmi|server.rmi.ssl.keystore.alias=rmi|" 
    

}

update_config_boss()
{
    export LANGUAGE=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
    export LANG=en_US.UTF-8
    export LC_TYPE=en_US.UTF-8
    wget -O /opt/jmeter/apache-jmeter-5.0/bin/rmi_keystore.jks https://github.com/siggeb/jmeter-public/raw/master/elasticsearch-jmeter/resources/rmi_keystore.jks
    wget -O /opt/jmeter/apache-jmeter-5.0/bin/user.properties https://github.com/siggeb/jmeter-public/raw/master/elasticsearch-jmeter/resources/user.properties
    mv /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties.bak
    #cat /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties.bak | sed "s|remote_hosts=127.0.0.1|remote_hosts=${REMOTE_HOSTS}|" | sed "s|#server.rmi.ssl.disable=false|server.rmi.ssl.disable=false|" > /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties 

    #cat /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties.bak | sed "s|#client.rmi.localport=0|client.rmi.localport=4440|" | sed "s|remote_hosts=127.0.0.1|remote_hosts=${REMOTE_HOSTS}|" | sed "s|#server.rmi.ssl.disable=false|server.rmi.ssl.disable=false|" | sed "s|#server.rmi.ssl.keystore.type=JKS|server.rmi.ssl.keystore.type=JKS|" | sed "s|#server.rmi.ssl.keystore.file=rmi_keystore.jks|server.rmi.ssl.keystore.file=/opt/jmeter/apache-jmeter-5.0/bin/rmi_keystore.jks|" | sed "s|#server.rmi.ssl.keystore.password=changeit|server.rmi.ssl.keystore.password=changeit|" | sed "s|#server.rmi.ssl.keystore.alias=rmi|server.rmi.ssl.keystore.alias=rmi|" > /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties 
    
    cat /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties.bak | sed "s|remote_hosts=127.0.0.1|remote_hosts=${REMOTE_HOSTS}|" > /opt/jmeter/apache-jmeter-5.0/bin/jmeter.properties 


    #| sed "s|#server.rmi.ssl.keystore.type=JKS|server.rmi.ssl.keystore.type=JKS|" | sed "s|#server.rmi.ssl.keystore.file=rmi_keystore.jks|server.rmi.ssl.keystore.file=/opt/jmeter/apache-jmeter-5.0/bin/rmi_keystore.jks|" | sed "s|#server.rmi.ssl.keystore.password=changeit|server.rmi.ssl.keystore.password=changeit|" | sed "s|#server.rmi.ssl.keystore.alias=rmi|server.rmi.ssl.keystore.alias=rmi|" 
    
    
    
}

install_jmeter()
{
    log "Installing JMeter"
    apt-get -y install unzip 
    
    mkdir -p /opt/jmeter
    wget -O jmeter.zip https://archive.apache.org/dist/jmeter/binaries/apache-jmeter-5.0.zip
    
    log "unzipping jmeter"
    unzip -q jmeter.zip -d /opt/jmeter/
    
    log "installing plugins manager"
    wget -O /opt/jmeter/apache-jmeter-5.0/lib/ext/jmeter-plugins-manager-1.3.jar https://jmeter-plugins.org/get/
    
    log "getting test plan"
    wget -O /opt/jmeter/RNB_POP_preprod_JMeter_ChromeDriver.jmx https://raw.githubusercontent.com/siggeb/jmeter-public/master/elasticsearch-jmeter/resources/RNB_POP_preprod_JMeter_ChromeDriver.jmx
    
    log "installing plugins"
    wget -O /opt/jmeter/apache-jmeter-5.0/lib/cmdrunner-2.2.jar http://search.maven.org/remotecontent?filepath=kg/apc/cmdrunner/2.2/cmdrunner-2.2.jar
    java -cp /opt/jmeter/apache-jmeter-5.0/lib/ext/jmeter-plugins-manager-1.3.jar org.jmeterplugins.repository.PluginManagerCMDInstaller
    /opt/jmeter/apache-jmeter-5.0/bin/PluginsManagerCMD.sh install-for-jmx /opt/jmeter/RNB_POP_preprod_JMeter_ChromeDriver.jmx

     
    chmod u+x /opt/jmeter/apache-jmeter-5.0/bin/jmeter-server
    chmod u+x /opt/jmeter/apache-jmeter-5.0/bin/jmeter
    
    
    if [ ${IS_MASTER} -ne 1 ]; 
    then
        log "setting up sub node"
        iptables -A INPUT -m state --state NEW -m tcp -p tcp --match multiport --dports 1000:5000 -j ACCEPT
        
        update_config_sub
        setup_jmeter_service
    else
        log "setting up boss node"
        iptables -A INPUT -p tcp --match multiport --dports 1000:5000 -j ACCEPT
        iptables -A OUTPUT -p tcp --match multiport --dports 1000:5000 -j ACCEPT
    
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
    #wget -q -O - https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
    #sh -c 'echo "deb http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list'
    
    apt-get -y update  > /dev/null
    apt-get -qy install wget default-jre-headless telnet iputils-ping unzip libnss3  #chromium-chromedriver > /dev/null
    wget -q https://chromedriver.storage.googleapis.com/2.37/chromedriver_linux64.zip
    unzip chromedriver_linux64.zip
    sudo mv chromedriver /usr/bin/chromedriver
    sudo chown root:root /usr/bin/chromedriver
    sudo chmod +x /usr/bin/chromedriver
    
    apt-get install libxss1 libappindicator1 libindicator7
    wget http://security.ubuntu.com/ubuntu/pool/universe/c/chromium-browser/chromium-browser_65.0.3325.181-0ubuntu0.14.04.1_amd64.deb
    dpkg -i chromium-browser*.deb
    apt-get install -f
    dpkg -i chromium-browser*.deb
    
    
    
    #dpkg -i google-chrome*.deb
    #apt-get install -f
    #dpkg -i google-chrome*.deb
    
    #why is this symlink needed? 
    #sudo ln -s /usr/lib/chromium-browser/chromedriver /usr/bin/chromedriver
    
    #log "Installing n"
    #npm install -g n
    #npm config set strict-ssl false
    #n stable
    #log "Done installing n"

    
    #npm install -g chromedriver #> /dev/null
    #ln -s /home/avensia/node_modules/chromedriver/lib/chromedriver/chromedriver /usr/bin
    log "Chromedriver installed and alias created in /usr/bin"
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
create_jmeter_startup_script

log "script complete"
