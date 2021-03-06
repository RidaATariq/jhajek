#!/bin/bash 
set -e
set -v

# http://superuser.com/questions/196848/how-do-i-create-an-administrator-user-on-ubuntu
# http://unix.stackexchange.com/questions/1416/redirecting-stdout-to-a-file-you-dont-have-write-permission-on
echo "vagrant ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/init-users
sudo cat /etc/sudoers.d/init-users

# Installing vagrant keys
wget --no-check-certificate 'https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub'
sudo mkdir -p /home/vagrant/.ssh
cat ./vagrant.pub >> /home/vagrant/.ssh/authorized_keys
sudo chown -R vagrant:vagrant /home/vagrant/.ssh
##################################################
# Change hostname and /etc/hosts
##################################################
cat << EOT >> /etc/hosts
# Nodes
192.168.33.110 riemanna riemanna.example.com
192.168.33.120 riemannb riemannb.example.com
192.168.33.100 riemannmc riemannmc.example.com
192.168.33.210 graphitea graphitea.example.com
192.168.33.220 graphiteb graphiteb.example.com
192.168.33.200 graphitemc graphitemc.example.com
192.168.33.150 ela1 ela1.example.com
192.168.33.160 ela2 ela2.example.com
192.168.33.170 ela3 ela3.example.com
192.168.33.180 logstash logstash.example.com
192.168.33.10 host1 host1.example.com
192.168.33.11 host2 host2.example.com
192.168.33.140 docker1 docker1.example.com
EOT

sudo hostnamectl set-hostname riemannmc

##################################################
sudo apt-get update -y
sudo apt-get install -y ruby ruby-dev build-essential zlib1g-dev openjdk-8-jre 

# P.42 The Art of Monitoring
wget https://github.com/riemann/riemann/releases/download/0.3.5/riemann_0.3.5_all.deb
sudo dpkg -i riemann_0.3.5_all.deb

# cloning source code examples for the book
git clone https://github.com/turnbullpress/aom-code.git

sudo cp -rv /home/vagrant/aom-code/5-6/riemann/examplecom /etc/riemann/

sudo sed -i 's/graphitea/graphitemc/g' /etc/riemann/examplecom/etc/graphite.clj
sudo sed -i 's/productiona/productionmc/g' /etc/riemann/examplecom/etc/graphite.clj

# Install leiningen on Ubuntu - needed for riemann syntax checker
sudo apt-get install -y leiningen

# Riemann syntax checker download and install
git clone https://github.com/samn/riemann-syntax-check
cd riemann-syntax-check
lein uberjar
cd ../

# Adding the raw content of the chapter 5-6 riemann.config file
cat << EOT > /etc/riemann/riemann.config
(logging/init {:file "/var/log/riemann/riemann.log"})

(require 'riemann.client)
(require '[examplecom.etc.email :refer :all])
(require '[examplecom.etc.graphite :refer :all])
(require '[examplecom.etc.collectd :refer :all])

(let [host "0.0.0.0"]
  (repl-server {:host "127.0.0.1"})
  (tcp-server {:host host})
  (udp-server {:host host})
  (ws-server  {:host host}))

(periodically-expire 10 {:keep-keys [:host :service :tags, :state, :description, :metric]})

(let [index (index)]

  ; Inbound events will be passed to these streams:
  (streams
    (default :ttl 60
      ; Index all events immediately.
      (where (not (tagged "notification"))
        index)

      (tagged "collectd"
        (smap rewrite-service graph)

        (tagged "notification"
          (changed-state {:init "ok"}
            (adjust [:service clojure.string/replace #"^processes-(.*)\/ps_count$" "$1"]
              (email "james@example.com"))))

         (where (and (expired? event)
                     (service #"^processes-.+\/ps_count\/processes"))
           (adjust [:service clojure.string/replace #"^processes-(.*)\/ps_count\/processes$" "$1"]
             (email "james@example.com"))))

      (where (service #"^riemann.*")
        graph

        downstream))))

EOT


sudo systemctl enable riemann
sudo systemctl start riemann 


