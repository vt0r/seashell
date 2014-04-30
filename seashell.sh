#!/bin/bash
##-------------
# Seashell.sh
# -------------
# Copyright (C) 2013 by Salvatore LaMendola
# For full licensing information, see LICENSE
##-------------
# Do you love DigitalOcean?
# I love it, and so does your mom.
##---
# The website and control panel are so amazingly simple,
# but wouldn't it be even simpler to just go to your
# terminal for creating/deleting droplets, etc?
# Of course it would! Let's get started with configuration.
##

# Enter your client ID here
CLIENTID=""

# Enter your API key here
APIKEY=""

## That's all for the configuration!

# Let's make sure you didn't screw up the config!
if [ -z "$CLIENTID" ]; then
  echo "Missing Client ID. Edit $0 and adjust CLIENTID variable"
  exit 1
fi
if [ -z "$APIKEY" ]; then
  echo "Missing API key. Edit $0 and adjust APIKEY variable"
  exit 1
fi

## BEGIN JSON.sh
# Code stolen from https://github.com/dominictarr/JSON.sh
JSONsh() {
  throw () {
    echo "$*" >&2
    exit 1
  }

  BRIEF=0
  LEAFONLY=1
  PRUNE=0

  awk_egrep () {
    local pattern_string=$1

    gawk '{
      while ($0) {
        start=match($0, pattern);
        token=substr($0, start, RLENGTH);
        print token;
        $0=substr($0, start+RLENGTH);
      }
    }' pattern=$pattern_string
  }

  tokenize () {
   local GREP
   local ESCAPE
   local CHAR

   if echo "test string" | egrep -ao --color=never "test" &>/dev/null
   then
     GREP='egrep -ao --color=never'
   else
     GREP='egrep -ao'
   fi

    if echo "test string" | egrep -o "test" &>/dev/null
   then
     ESCAPE='(\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})'
     CHAR='[^[:cntrl:]"\\]'
   else
     GREP=awk_egrep
     ESCAPE='(\\\\[^u[:cntrl:]]|\\u[0-9a-fA-F]{4})'
     CHAR='[^[:cntrl:]"\\\\]'
   fi

   local STRING="\"$CHAR*($ESCAPE$CHAR*)*\""
   local NUMBER='-?(0|[1-9][0-9]*)([.][0-9]*)?([eE][+-]?[0-9]*)?'
   local KEYWORD='null|false|true'
   local SPACE='[[:space:]]+'

    $GREP "$STRING|$NUMBER|$KEYWORD|$SPACE|." | egrep -v "^$SPACE$"
  }

  parse_array () {
   local index=0
   local ary=''
   read -r token
   case "$token" in
     ']') ;;
     *)
       while :
       do
         parse_value "$1" "$index"
         index=$((index+1))
         ary="$ary""$value" 
         read -r token
         case "$token" in
           ']') break ;;
           ',') ary="$ary," ;;
           *) throw "EXPECTED , or ] GOT ${token:-EOF}" ;;
         esac
         read -r token
       done
       ;;
   esac
   [ "$BRIEF" -eq 0 ] && value=`printf '[%s]' "$ary"` || value=
   :
  }

  parse_object () {
   local key
   local obj=''
   read -r token
   case "$token" in
     '}') ;;
     *)
       while :
       do
         case "$token" in
           '"'*'"') key=$token ;;
           *) throw "EXPECTED string GOT ${token:-EOF}" ;;
         esac
         read -r token
         case "$token" in
           ':') ;;
           *) throw "EXPECTED : GOT ${token:-EOF}" ;;
         esac
         read -r token
         parse_value "$1" "$key"
         obj="$obj$key:$value"        
         read -r token
         case "$token" in
            '}') break ;;
           ',') obj="$obj," ;;
           *) throw "EXPECTED , or } GOT ${token:-EOF}" ;;
         esac
         read -r token
       done
     ;;
    esac
    [ "$BRIEF" -eq 0 ] && value=`printf '{%s}' "$obj"` || value=
    :
  }

  parse_value () {
   local jpath="${1:+$1,}$2" isleaf=0 isempty=0 print=0
   case "$token" in
     '{') parse_object "$jpath" ;;
     '[') parse_array  "$jpath" ;;
     # At this point, the only valid single-character tokens are digits.
     ''|[!0-9]) throw "EXPECTED value GOT ${token:-EOF}" ;;
     *) value=$token
        isleaf=1
        [ "$value" = '""' ] && isempty=1
        ;;
   esac
   [ "$value" = '' ] && return
   [ "$LEAFONLY" -eq 0 ] && [ "$PRUNE" -eq 0 ] && print=1
   [ "$LEAFONLY" -eq 1 ] && [ "$isleaf" -eq 1 ] && [ $PRUNE -eq 0 ] && print=1
   [ "$LEAFONLY" -eq 0 ] && [ "$PRUNE" -eq 1 ] && [ "$isempty" -eq 0 ] && print=1
   [ "$LEAFONLY" -eq 1 ] && [ "$isleaf" -eq 1 ] && \
     [ $PRUNE -eq 1 ] && [ $isempty -eq 0 ] && print=1
   [ "$print" -eq 1 ] && printf "[%s]\t%s\n" "$jpath" "$value"
   :
  }

  parse () {
   read -r token
   parse_value
   read -r token
   case "$token" in
     '') ;;
     *) throw "EXPECTED EOF GOT $token" ;;
   esac
  }

  if ([ "$0" = "$BASH_SOURCE" ] || ! [ -n "$BASH_SOURCE" ]);
  then
   tokenize | parse
  fi
}
## END JSON.sh

# Functions for the actual API calls

# Get unaltered list of droplets
getdroplets() {
    curl -ks "https://api.digitalocean.com/droplets/?client_id=$CLIENTID&api_key=$APIKEY"
}
# Let's get the same list, but make it easy to read
parseddroplets() {
    parsedout=`getdroplets | JSONsh`
    cmdstatus=`echo "$parsedout" | head -n 1 | awk '{print $2}' | tr -d '"'`

    # Check for OK on request or die
    if [ "$cmdstatus" != "OK" ]; then
        echo "$parsedout"
        exit 1
    fi

    count='0'
    maxcount=`echo "$parsedout" | tail -n 1 | awk -F, '{print $2}'`
    regionlist=`parsedregions`
    sizeslist=`parsedsizes`
    imageslist=`parsedimages`
    IFS=$'\n'

    # Display the status of the request
    echo -e "Request status: $cmdstatus\n"

    # Use the index given from JSONsh output to separate
    # entries into separate items, then print results
    while [ "$count" -le "$maxcount" ]; do
        for i in `echo "$parsedout" | grep "\",$count,\""`; do
            ID=`echo $i | grep ',"id"'`
            NAME=`echo $i | grep ',"name"'`
            IMAGE=`echo $i | grep ',"image_id"'`
            SIZEID=`echo $i | grep ',"size_id"'`
            REGION=`echo $i | grep ',"region_id"'`
            BACKUPS=`echo $i | grep ',"backups_active"'`
            IP=`echo $i | grep ',"ip_address"'`
            STATUS=`echo $i | grep ',"status"'`
            CREATED=`echo $i | grep ',"created_at"'`
            if [ -n "$ID" ]; then
                id=`echo $i | awk '{print $2}' | tr -d '"'`
            elif [ -n "$NAME" ]; then
                name=`echo "$i" | awk '{print $2}' | tr -d '"'`
            elif [ -n "$IMAGE" ]; then
                imageid=`echo "$i" | awk '{print $2}' | tr -d '"'`
                image=`echo "$imageslist" | grep "Image ID: $imageid" | awk -F\- '{print $3}'`
            elif [ -n "$SIZEID" ]; then
                sizeid=`echo "$i" | awk '{print $2}' | tr -d '"'`
                size=`echo "$sizeslist" | grep "Size ID: $sizeid" | awk -F\- '{print $2}'`
            elif [ -n "$REGION" ]; then
                regionid=`echo "$i" | awk '{print $2}' | tr -d '"'`
                region=`echo "$regionlist" | grep "Region ID: $regionid" | awk -F\- '{print $3 " " $4 " " $5}'`
            elif [ -n "$BACKUPS" ]; then
                backups=`echo "$i" | awk '{print $2}' | tr -d '"'`
            elif [ -n "$IP" ]; then
                ip=`echo "$i" | awk '{print $2}' | tr -d '"'`
            elif [ -n "$STATUS" ]; then
                status=`echo "$i" | awk '{print $2}' | tr -d '"'`
            elif [ -n "$CREATED" ]; then
                created=`echo "$i" | awk '{print $2}' | tr -d '"' | tr 'T' ' ' | sed -e 's/Z/ UTC/g'`
            fi
        done
        echo -e "$(($count + 1)). ID: $id \n   Name: $name \n   Image: $image \n   Size:$size \n   Region:$region \n   Backups Enabled: $backups \n   IP: $ip \n   Status: $status \n   Created: $created\n"
        count=$(($count + 1))
    done
}

# Get available sizes for new droplets
getsizes() {
    curl -ks "https://api.digitalocean.com/sizes/?client_id=$CLIENTID&api_key=$APIKEY"
}
# Let's get the same list, but make it easy to read
parsedsizes() {
    parsedout=`getsizes | JSONsh | grep -v "slug"`
    cmdstatus=`echo "$parsedout" | head -n 1 | awk '{print $2}' | tr -d '"'`

    # Check for OK on request or die
    if [ "$cmdstatus" != "OK" ]; then
        echo "$parsedout"
        exit 1
    fi

    count='0'
    maxcount=`echo "$parsedout" | tail -n 1 | awk -F, '{print $2}'`
    IFS=$'\n'

    # Display the status of the request
    echo -e "Request status: $cmdstatus\n"

    # Use the index given from JSONsh output to separate
    # entries into separate items, then print id/name
    while [ "$count" -le "$maxcount" ]; do
        for i in `echo "$parsedout" | grep "\",$count,\""`; do
            ID=`echo $i | grep ',"id"'`
            if [ -n "$ID" ]; then
                id=`echo $i | awk '{print $2}' | tr -d '"'`
            else
                size=`echo "$i" | awk '{print $2}' | tr -d '"'`
            fi
        done
        echo "Size ID: $id - $size"
        count=$(($count + 1))
    done
}

# Get available sizes for new droplets
getregions() {
    curl -ks "https://api.digitalocean.com/regions/?client_id=$CLIENTID&api_key=$APIKEY"
}
# Let's get the same list, but make it easy to read
parsedregions() {
    parsedout=`getregions | JSONsh`
    cmdstatus=`echo "$parsedout" | head -n 1 | awk '{print $2}' | tr -d '"'`

    # Check for OK on request or die
    if [ "$cmdstatus" != "OK" ]; then
        echo "$parsedout"
        exit 1
    fi

    count='0'
    maxcount=`echo "$parsedout" | tail -n 1 | awk -F, '{print $2}'`
    IFS=$'\n'

    # Display the status of the request
    echo -e "Request status: $cmdstatus\n"

    # Use the index given from JSONsh output to separate
    # entries into separate items, then print results
    while [ "$count" -le "$maxcount" ]; do
        for i in `echo "$parsedout" | grep "\",$count,\""`; do
            ID=`echo $i | grep ',"id"'`
            NAME=`echo $i | grep ',"name"'`
            SLUG=`echo $i | grep ',"slug"'`
            if [ -n "$ID" ]; then
                id=`echo $i | awk '{print $2}' | tr -d '"'`
            elif [ -n "$NAME" ]; then
                name=`echo "$i" | awk -F\" '{print $6}' | tr -d '"'`
            elif [ -n "$SLUG" ]; then
                slug=`echo "$i" | awk '{print $2}' | tr -d '"'`
            fi
        done
        echo "Region ID: $id - $slug - $name"
        count=$(($count + 1))
    done
}

# Get available images and their IDs
getimages() {
    curl -ks "https://api.digitalocean.com/images/?client_id=$CLIENTID&api_key=$APIKEY"
}
# Let's get the same list, but make it easy to read
parsedimages() {
    parsedout=`getimages | JSONsh`
    cmdstatus=`echo "$parsedout" | head -n 1 | awk '{print $2}' | tr -d '"'`

    # Check for OK on request or die
    if [ "$cmdstatus" != "OK" ]; then
        echo "$parsedout"
        exit 1
    fi

    count='0'
    maxcount=`echo "$parsedout" | tail -n 1 | awk -F, '{print $2}'`
    IFS=$'\n'

    # Display the status of the request
    echo -e "Request status: $cmdstatus\n"

    # Use the index given from JSONsh output to separate
    # entries into separate items, then print results
    while [ "$count" -le "$maxcount" ]; do
        for i in `echo "$parsedout" | grep "\",$count,\""`; do
            ID=`echo $i | grep ',"id"'`
            NAME=`echo $i | grep ',"name"'`
            SLUG=`echo $i | grep ',"slug"'`
            DISTRO=`echo $i | grep ',"distribution"'`
            if [ -n "$ID" ]; then
                id=`echo $i | awk '{print $2}' | tr -d '"'`
            elif [ -n "$NAME" ]; then
                name=`echo "$i" | awk -F\" '{print $6}' | tr -d '"'`
            elif [ -n "$SLUG" ]; then
                slug=`echo "$i" | awk '{print $2}' | tr -d '"'`
            elif [ -n "$DISTRO" ]; then
                distro=`echo "$i" | awk -F\" '{print $6}' | tr -d '"'`
            fi
        done
        echo "Image ID: $id - $slug - $name - $distro"
        count=$(($count + 1))
    done
}

# Get available SSH keys and their IDs/names
getsshkeys() {
    curl -ks "https://api.digitalocean.com/ssh_keys/?client_id=$CLIENTID&api_key=$APIKEY"
}
parsedsshkeys() {
    parsedout=`getsshkeys | JSONsh`
    cmdstatus=`echo "$parsedout" | head -n 1 | awk '{print $2}' | tr -d '"'`

    # Check for OK on request or die
    if [ "$cmdstatus" != "OK" ]; then
        echo "$parsedout"
        exit 1
    fi

    count='0'
    maxcount=`echo "$parsedout" | tail -n 1 | awk -F, '{print $2}'`
    IFS=$'\n'

    # Display the status of the request
    echo -e "Request status: $cmdstatus\n"

    # Use the index given from JSONsh output to separate
    # entries into separate items, then print results
    while [ "$count" -le "$maxcount" ]; do
        for i in `echo "$parsedout" | grep "\",$count,\""`; do
            ID=`echo $i | grep ',"id"'`
            NAME=`echo $i | grep ',"name"'`
            if [ -n "$ID" ]; then
                id=`echo $i | awk '{print $2}' | tr -d '"'`
            elif [ -n "$NAME" ]; then
                name=`echo "$i" | awk -F\" '{print $6}' | tr -d '"'`
            fi
        done
        echo "SSH Key ID: $id - $name"
        count=$(($count + 1))
    done
}

## POC for now!
## Just uncomment any of the below functions to list droplets, sizes, regions, images, SSH keys
## in a nicely-parsed format. Soon, the destructive commands will get added here and this
## will be a fully functional API client!
#parseddroplets
#parsedsizes
#parsedregions
#parsedimages
#parsedsshkeys

exit 0
