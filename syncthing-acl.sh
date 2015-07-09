#!/bin/bash
#set -x
#    Copyright 1998, 1999 Gary Seymour
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

REPOSITORY="/export/storage"
ACLPATH="$REPOSITORY/.acls"
APPNAME="syncthing-acl"
TEMPACLFILE=/tmp/$APPNAME.$$
IGNOREFILES="\.syncthing|\.stversions|\.stfolder|lost\+found"
PIDFOLDER=/var/run/$APPNAME
PIDFILE=/var/run/$APPNAME/$APPNAME.pid
FILEJITTER=120
VERSION="0.5 09/07/15"
LOGGEROPTS="-s"
LOGLEVEL=1
DEBUGMESSAGELEVEL=3
WAITTIME=2


#=========Logger

syncthing-log() {
	# $1 Log Level $2 Message
	if (( $1 <= $LOGLEVEL )); then
	 	logger $LOGGEROPTS -t $APPNAME "$2"
	fi
}
export -f syncthing-log

#=========Check DIFF Between Two Files

checkfilediff() {
	f1="$1"
	f2="$2"
	t1=`stat -c%Y $f1`
	t2=`stat -c%Y $f2`
	[[ $t1 -gt $t2 ]] && diff=` echo $t1 - $t2 | bc ` || diff=` echo $t2 - $t1 | bc `
	[[ $diff -lt $FILEJITTER ]] && return 0 || return 1 
}
export -f checkfilediff

checkdirdiff() {
# Check Directory Time Difference is Tollerable. $1=ACLFILE, $2=REPFile(=Directory)
# We Allow ACLFile >= REPFile or REPFile - ACLFile < FILEJITTER
	AF="$1"
	RD="$2"
	t1=`stat -c%Y "$AF"`
	t2=`stat -c%Y "$RD"`
	[[ $t1 -ge $t2 ]] && return 0 
        diff=` echo $t2 - $t1 | bc `
	[[ $diff -le $FILEJITTER ]] && return 0
	return 1 
}
export -f checkdirdiff

#=========Check Contents of a List

listcontains() {
  RESULT=1
  for word in "$1"; do
    [[ $word = "$2" ]] && RESULT=0 && break
  done
  return $RESULT
}

#=========Set File Owners based on an ACL File

setusergroup() {
  F="$1"
  AF="$2"
  AU=`sed -n 's|^# owner: \(.*\)$|\1|p' "$AF"`
  AG=`sed -n 's|^# group: \(.*\)$|\1|p' "$AF"`
  OU=`stat -c%U "$F"`
  OG=`stat -c%G "$F"`
  if [ "$AU" != "$OU" ] && [ "$AG" != "$OG" ]; then
  	chown $AU:$AG $F
  elif [ "$AG" != "$OG" ]; then
  	chgrp $AG $F
  elif [ "$AU" != "$OU" ]; then
	chown $AU $F
  fi
}
export -f setusergroup

#=========Check / Reset All Files

file-check() {
  	filename="$1"

        if echo "$filename" | egrep "$IGNOREFILES" >/dev/null ; then
		ACTION="Do Nothing: Syncthing Control File" ; MESSAGELEVEL=3
	elif [[ "$filename" == "$REPOSITORY" ]]  ; then #Ignore .acl Path
		ACTION="Do Nothing: Parent Folder" ; MESSAGELEVEL=3
	elif [[ "$filename" =~ "$ACLPATH" ]]  ; then #Ignore .acl Path
		ACTION="Do Nothing: ACL Folders"  ; MESSAGELEVEL=3
	else
		subpath="${filename#$REPOSITORY}"
		subpath=`echo $subpath | sed -e 's/^\///' -e 's#/$##'`
		subfile=`basename "$subpath"`
		subfolder="${subpath%/$subfile}"
		REPFile="$REPOSITORY/$subfolder/$subfile"
		ACLFOLDER="$ACLPATH/$subfolder"
		[ -d "$REPFile"  ] && ACLFILE="$ACLFOLDER/${subfile}_folder" || ACLFILE="$ACLFOLDER/$subfile"
		if [ ! -f "$ACLFILE" ]; then
			ACTION="Do Nothing: NO ACL File"  ; MESSAGELEVEL=3
		elif [ -d "$REPFile" ] &&  !( checkdirdiff "$ACLFILE" "$REPFile" ); then
			ACTION="Do Nothing: ACL File Older than REPFile (DIRECTORY)" ; MESSAGELEVEL=2
		elif [ -f "$REPFile" ] && [ -d "$ACLFILE" ]; then
                        ACTION="Fix ACL File, ACL is a Directory, RepFile isnt" ; MESSAGELEVEL=1
                        rm -rf "$ACLFILE"
                        getfacl -p "$REPFile" >"$TEMPACLFILE.file-check"
                        touch --reference="$REPFile" "$TEMPACLFILE.file-check"
                        mv "$TEMPACLFILE.file-check" "$ACLFILE"
		elif [ -f "$REPFile" ] && [ "$ACLFILE" -ot "$REPFile" ]; then
			ACTION="Do Nothing: ACL File Older than REPFile " ; MESSAGELEVEL=2
		else
			getfacl -p "$REPFile" >$TEMPACLFILE.file-check
                        if ! ( diff "$ACLFILE" "$TEMPACLFILE.file-check" >/dev/null )   ; then
				setfacl -M "$ACLFILE" "$REPFile"
				setusergroup "$REPFile" "$ACLFILE"
				ACTION="Update/Fix ACL: ACLFile Newer & Different than REPFile "  ; MESSAGELEVEL=1
			else
				ACTION="Do Nothing: ACL File Same as REPFile " ; MESSAGELEVEL=3
			fi
		fi	
	fi
	syncthing-log $MESSAGELEVEL "$EVENTTYPE : $ACTION : ACLFile=$ACLFILE REPFile=$REPFile Filename=$filename"
	syncthing-log $DEBUGMESSAGELEVEL "Debug : : subfile=$subfile subpath=$subpath subfile=$subfile subfolder=$subfolder"
}
export -f file-check

dir-check() {
	EVENTTYPE="INITIAL ACL Check" ; MESSAGELEVEL=2

	find "$REPOSITORY" -print0 | while IFS= read -r -d '' file; do
		file-check "$file"
	done
	EVENTTYPE="BACKGROUND ACL Check" ; MESSAGELEVEL=2
	while true; do
		find "$REPOSITORY" -print0 | while IFS= read -r -d '' file; do
			file-check "$file"
			sleep $WAITTIME
		done
	done
}
export -f dir-check

##########Exit Traps

exitcleanup() {
	#Function called on Exit
	rm -f "$TEMPACLFILE"
	syncthing-log 0 "Shutdown" 
	killall inotifywait
        if [ -f $PIDFILE.acl-check ]; then
		acl-check-pid=`cat $PIDFILE.acl-check`
        	kill -9 $acl-check-pid
		rm -f $PIDFILE.acl-check
        fi 
	syncthing-log 0 "Terminated" 
	exit
}
################### Print stuff

debug() {
echo $filename
echo $subpath
echo $subfile
echo $subfolder
echo $REPFile
echo $ACLFOLDER	
}

##########Main Starts

[ ! -d "$PIDFOLDER" ] && mkdir -p "$PIDFOLDER"
echo $$ > $PIDFILE

syncthing-log 0  "Start Up : Script $0 `stat -c%y $0` Version $VERSION PID=$$"

trap exitcleanup SIGHUP SIGINT SIGTERM

[ -d "$ACLPATH" ] || mkdir -p "$ACLPATH"

syncthing-log 0 "Starting Background ACL Check" 
dir-check &
acl_check_pid=$!
ionice -c 3 -p $acl_check_pid
echo $acl_check_pid > $PIDILE.acl-check
IFS=$','
inotifywait -rmc -e modify,delete,attrib,moved_to,moved_from,move,create "$REPOSITORY" --exclude "$IGNOREFILES" |
        while  read -a items ; do
            wf=${items[0]}
            events=${items[1]}
            if [ ${#items[*]} -eq 2 ] ; then
              ef=""
            elif [[ ! "${items[-1]}" =~ "ISDIR" ]]; then 
              ef=${items[-1]}
              for((i=2;i<${#items[@]}-1;i++)); do
    	        events="$events|${items[i]}"
              done
            else
              ef=""
              for((i=2;i<${#items[@]};i++)); do
    	        events="$events|${items[i]}"
              done
            fi
             [[ -z "$ef" ]] && filename=${wf%/} || filename="${wf%/}/${ef}"
		EVENTTYPE="ACL Event"; ACTION="Do Nothing"; MESSAGELEVEL=1
		if [[ "$filename" == "$ACLPATH" ]] ; then 					# ACL Parent Folder, Ignore
			EVENTTYPE="ACL Event"; ACTION="Do Nothing: ACL Home Folder"; MESSAGELEVEL=2
		elif [[ "$filename" =~ "$ACLPATH" ]] && [[ "$events" == *"ISDIR"* ]]  ; then 	# We dont need to Manage ACL Directories
			EVENTTYPE="ACL Event"; ACTION="Do Nothing: ACL Directories are not measured"; MESSAGELEVEL=2
		elif [[ "$filename" =~ "$ACLPATH" ]] ; then 					# ACL Event
			EVENTTYPE="ACL Event"
			[[ -d "$filename" ]]  && [[ "$filename" != *"_folder"  ]] && ACLFILE="${filename}_folder" || ACLFILE="$filename"
			subpath="${filename#$ACLPATH}"
			subpath=`echo $subpath | sed -e 's/^\///' `
			subfile=`basename "$subpath"`
			subfolder="${subpath%/$subfile}"
			[[ "$subfile" == *"_folder"  ]] && REPFile="$REPOSITORY/$subfolder/${subfile%_folder}" || REPFile="$REPOSITORY/$subfolder/$subfile"
			if [ ! -f "$REPFile" ] && [ ! -d "$REPFile" ]; then
				ACTION="Do Nothing: ACLFile Before REPFile" ; MESSAGELEVEL=2
               		elif [ -f "$REPFile" ] && [ -d "$ACLFILE" ] ; then
                        	ACTION="Fix ACL File, ACL is a Directory, RepFile isnt" ; MESSAGELEVEL=1
                                rm -rf "$ACLFILE"
				getfacl -p "$REPFile" >"$TEMPACLFILE"
				touch --reference="$REPFile" "$TEMPACLFILE"
				mv "$TEMPACLFILE" "$ACLFILE"
               		elif [ -d "$REPFile" ] && !( checkdirdiff "$ACLFILE" "$REPFile") ; then
                        	ACTION="Do Nothing: ACL File Older than REPFile (DIRECTORY Jitter)" ; MESSAGELEVEL=2
                	elif [ -f "$REPFile" ] && [ "$ACLFILE" -ot "$REPFile" ]; then
                        	ACTION="Do Nothing: ACL File Older than REPFile " ; MESSAGELEVEL=2
			else
				case $events in
				*CREATE* | *MODIFY* | *MOVED_TO* )				 # Check if ACLFile is different
					getfacl -p "$REPFile" >"$TEMPACLFILE"
                                        if ! ( diff "$ACLFILE" "$TEMPACLFILE" >/dev/null )   ; then
						setfacl -M "$ACLFILE" "$REPFile"
						setusergroup "$REPFile" "$ACLFILE"
						#touch --reference="$ACLFILE" "$REPFile"
						ACTION="Fix RepFile: Change Event, Set REPFile to ACLFile " ; MESSAGELEVEL=1
					else
						ACTION="Do Nothing: Change Event, but ACLFile & REPFile Identical" ; MESSAGELEVEL=2
					fi
					;;
           			*ATTRIB* | *MOVED_FROM* )				 #Do Nothing
					ACTION="Do Nothing: Ignore Event, ACLFile Newer than REPFile" ; MESSAGELEVEL=2
					;;
           			*DELETE*)	
					ACTION="Do Nothing: Ignore Event, ACLFile Deleted" ; MESSAGELEVEL=2
					;;
           			*MOVE*)	
					ACTION="Do Nothing: Ignore Event, ACLFile Moved " ; MESSAGELEVEL=2
					;;
				esac
			fi
		elif [[ "$filename" == "$REPOSITORY" ]] ; then 
			EVENTTYPE="FILE Event"; ACTION="Do Nothing: REPOSITORY Home Folder" ; MESSAGELEVEL=2
		else
			EVENTTYPE="FILE Event"
			subpath="${filename#$REPOSITORY}"
			subpath=`echo $subpath | sed -e 's/^\///'  -e 's#/$##'`
			subfile="$(basename $subpath)"
			subfolder="${subpath%/$subfile}"
			REPFile="$REPOSITORY/$subfolder/$subfile"
			ACLFOLDER="$ACLPATH/$subfolder"
#debug
			[[ "$events" =~ "ISDIR" ]] && ACLFILE="$ACLFOLDER"/"$subfile"_folder || [[ -d "$filename" ]] && ACLFILE="$ACLFOLDER"/"$subfile"_folder || ACLFILE="$ACLFOLDER"/"$subfile"
                        [[ -f "$REPFile" ]] && [[ -d "$ACLFILE" ]] && rm -rf "$ACLFILE"  # Fix bad ACLS
			case $events in
           			*ATTRIB* )					 # File File Date/Time Should Not be Updated
					[ -d "$ACLFOLDER" ] || mkdir -p "$ACLFOLDER"
					getfacl -p "$REPFile" >"$ACLFILE"
					ACTION="Create/Modify ACLFile, ACL Has Changed" ; MESSAGELEVEL=1
					;;
           			*CREATE* | *MODIFY* | *MOVE* | *MOVED_TO* )	 				# File Date/Time should be updated
					getfacl -p "$REPFile" >"$TEMPACLFILE"
					if [ -f "$ACLFILE" ] ; then
						if ! ( diff "$ACLFILE" "$TEMPACLFILE" >/dev/null )   ; then   # ACL File is Different than RepFile
               						if [ -d "$REPFile" ] && !( checkdirdiff "$ACLFILE" "$REPFile") ; then
                        					ACTION="Do Nothing: Change Event, But ACL File Older than REPFile (DIRECTORY Jitter)" ; MESSAGELEVEL=2
							else						 # Set to ACL File, cos its newer
								setfacl -M "$ACLFILE" "$REPFile"
								setusergroup "$REPFile" "$ACLFILE"
								#touch --reference="$ACLFILE" "$REPFILE"
								ACTION="Change File: Change Event, ACLFile Newer and Different"; MESSAGELEVEL=1
							fi
						else
							ACTION="Touch ACL: Change Event, ACLFile Identical to RepFile"; MESSAGELEVEL=1
							touch --reference="$REPFile" "$ACLFILE"
						fi
					else
						[[ -d "$ACLFOLDER" ]] || mkdir -p "$ACLFOLDER"
						touch --reference="$REPFile" "$TEMPACLFILE"
						mv "$TEMPACLFILE" "$ACLFILE"
						ACTION="Create ACL: Change Event, No ACLFile No Change to RepFile"; MESSAGELEVEL=1
					fi
					;;
           			*DELETE*)	
					rm -f "$ACLFILE"
					ACTION="Delete ACL: Delete Event, RepFile Delete" ; MESSAGELEVEL=1
					;;
           			*MOVED_FROM*)
					ACTION="Do Nothing: RepFile Removed" ; MESSAGELEVEL=2
					;;
			esac
		fi
		syncthing-log $MESSAGELEVEL "$EVENTTYPE : $ACTION : ACLFile=$ACLFILE REPFile=$REPFile Filename=$filename Events=$events"
		syncthing-log $DEBUGMESSAGELEVEL "Debug : : subfile=$subfile subpath=$subpath subfile=$subfile subfolder=$subfolder"
	done




