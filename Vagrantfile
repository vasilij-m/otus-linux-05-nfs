# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.box = "centos/7"
  config.vbguest.auto_update = false
  config.vm.synced_folder ".", "/vagrant", disabled: true

  config.vm.define "krb-srv" do |krb_srv|
    krb_srv.vm.network "private_network", ip: "192.168.10.30"
    krb_srv.vm.provider "virtualbox" do |v|
      v.memory = 1024
      v.cpus = 1
    end
    krb_srv.vm.hostname = "krb-srv"
    krb_srv.vm.provision "shell", path: "./skripts/krb_srv.sh", privileged: true
  end

  config.vm.define "nfs-srv" do |nfs_srv|
    nfs_srv.vm.network "private_network", ip: "192.168.10.10"
    nfs_srv.vm.provider "virtualbox" do |v|
      v.memory = 1024
      v.cpus = 1
    end
    nfs_srv.vm.hostname = "nfs-srv"
    nfs_srv.vm.provision "shell", path: "./skripts/krb_cl.sh", privileged: true
    nfs_srv.vm.provision "shell", path: "./skripts/nfs_srv.sh", privileged: true
  end

  config.vm.define "nfs-cl" do |nfs_cl|
    nfs_cl.vm.network "private_network", ip: "192.168.10.20"
    nfs_cl.vm.provider "virtualbox" do |v|
      v.memory = 1024
      v.cpus = 1
    end
    nfs_cl.vm.hostname = "nfs-cl"
    nfs_cl.vm.provision "shell", path: "./skripts/krb_cl.sh", privileged: true
    nfs_cl.vm.provision "shell", path: "./skripts/nfs_cl.sh", privileged: true
  end

  config.vm.provision "shell", path: "./skripts/initial_provisioning.sh", privileged: true

end
