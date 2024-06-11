#!/bin/bash

set -exu

declare -a toClean=()
cleanup() {
    for i in "${toClean[@]}";do
        rm -f "$i"
    done
}
trap cleanup EXIT

nextOperator=$(find operator -type d -path 'operator/*/*' |shuf |head -n 1)
if find $nextOperator -type f |grep -E '.+';then
    echo "Already processed"
    exit 0
fi
mcc=$(echo "$nextOperator" |cut -d / -f 2)
mnc=$(echo "$nextOperator" |cut -d / -f 3)
echo $mcc $mnc

rm -f $nextOperator/{status,google}

fqdn=config.rcs.mnc$mnc.mcc$mcc.pub.3gppnetwork.org
if ! host $fqdn;then
    fqdn=config.rcs.mnc0$mnc.mcc$mcc.pub.3gppnetwork.org
    if ! host $fqdn;then
        echo "DNS failed" > $nextOperator/status
        exit 0
    fi
fi

tmpfile=$(mktemp)
toClean+=($tmpfile)

proto=https
if ! timeout 1 openssl s_client -host $fqdn -port 443 </dev/null 2>$tmpfile;then
    echo "Failed to connect to port 443" > $nextOperator/status
    if timeout 1 curl http://$fqdn;then
        proto=http
    else
        echo "Failed to connect to port 80" >> $nextOperator/status
        exit 0
    fi
fi

if grep 'Google Trust Services' $tmpfile;then
    echo "Google SSL" > $nextOperator/google
fi

imsi_suffix=""
if echo "$mnc" |grep -E '^..$';then
    imsi_suffix=1
fi

tmpfile2=$(mktemp)
toClean+=(tmpfile2)
curl -vL "${proto}://$fqdn/?terminal_vendor=SamsungB&terminal_model=SM-N920T&client_version=RCSAndrd-1.0&IMSI="$mcc$mnc$imsi_suffix"087937984&terminal_sw_version=N920TUVS2COKC&client_vendor=SEC&vers=0&rcs_profile=UP_2.4&Token=&SMS_port=37273&msisdn=+33646106146&instance_id_token=cmV3am9wZGVxcG8K&cs_version=5.1B&rcs_version=11.0" > $tmpfile 2> $tmpfile2 || true

cp $tmpfile $nextOperator/dumbanswer
cp $tmpfile2 $nextOperator/dumbanswer-ssl

if grep 'using HTTP/2' $tmpfile;then
    echo "Using HTTP/2" >> $nextOperator/google
fi

if grep -E 'HTTP/.{1,10}200' $tmpfile2;then
    echo "Got a 200 on obviously wrong IMSI/MSISDN" > $nextOperator/status
    if ! xmlstarlet val $tmpfile;then
        echo "Responded with an invalid answer" >> $nextOperator/status
    else
        if [ "$(xmlstarlet sel -t -m '//characteristic/parm[@name="version"]' -v ./@value -n $tmpfile)" = 0 ] && [ "$(xmlstarlet sel -t -m //characteristic/parm -v ./@name -o ';' $tmpfile)" = "version;validity;" ];then
            echo "Highly likely to be a Jibe OOB server" >> $nextOperator/google
        fi
    fi
    exit 0
fi
echo "Yay" >> $nextOperator/status
