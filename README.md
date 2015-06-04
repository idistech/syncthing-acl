# syncthing-acl
Syncthing-acl is a daemon that supports syncthing to provide replication of file ownership and permissions across syncthing folders/hosts. It runs in parallel to the syncthing daemon, and asynchronously attempts to keep the file systems aligned.

This application has been tested on Ubuntu 12.04, and 14.04, and should work on other later releases.
It should work on Debian, and might work on other distro's, as written in BASH its portable.
It is Alpha release, so please use at your own risk.

Syncthing Should be installed and running on the host, as user root.
Install syncthing-acl on each server that is running syncthing.

##Version
0.4 Alpha , No Warrenty is provided, Syncthing-acl may screw up your user:group ownerships and permissions for all files under the REPOSITORY parent folder.

## How Does it work.
Syncthing-acl uses a hidden folder '.acl' to keep a record of all file permissions and ownerships under its REPOSITORY. Everytime a file changes, syncthing-acl writes a record ( a file ) to the .acl directory. Syncthing then propoagtes these ACL files, and the syncthing-acl daemon on other machines then sets the permissions accordingly as the ACL file arrives.
Syncthing needs to be setup to have a Folder/Repository that replicates the .acl folder. 
Syncthing-acl assumes that there is a top level folder that contains all Syncthing sync folders, ie you can have as many syncthing folders as you like, as long as they all sit under one master parent directory, this master directory ("REPOSITORY") contains the .acls folder.
eg
Repository Folder = /export/storage
ACL Folder = /export/storage/.acls

Syncthing has one or more sync folders under the /export/storage parent, ( eg /export/storage/folder1, folder2 etc ) plus one additional syncfolder '.acls'
Users and Groups must exist on all servers.

It is probably better at filesystems/folders that grow, and change little/infrequent, rather than are being constantly modified. It uses a 'FILEJITTER' setting to manage delays in propogation. 

## Prerequisites
i) Install inotify-tools and acl : apt-get install inotify-tools acl
ii) Ensure all syncthing servers are timesynced.

## To Install
1) install -t /usr/local/bin -g root -o root -m 0774 syncthing-acl.sh
2) install -t /etc/init -g root -o root -m 0640 syncthing.conf
3) Edit /usr/local/bin/syncthing-acl.sh and edit RESPOSITORY
4) Start the daemon , 
   service syncthing-acl start
, output is sent to /var/log/syslog. You can start the process on the commandline if you want to watch it. ( "/usr/local/bin/syncthing-acl.sh" ). You can set the LOGLevel to manage the level of debug.
5) Update/Set your syncthing daemon to replicate the .acls folder ( without any backup or versioning ).

## To Do
i) Auto create Users and Groups if found
ii) rewrite this in something more useful like perl, this is really beyond where bash should be used
iii) Possibly read folder config from Syncthing, and automatically generate .acls folders under each syncthing folder.
iv) more recovery modes in the event of failure ( unknown but suspected )
v) Race conditions ? May Occur, but unknown.
vi) Package installation, ppa etc.
