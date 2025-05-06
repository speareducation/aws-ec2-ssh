#!/bin/bash -e

if [ -z "$1" ]; then
  exit 1
fi

# check if AWS CLI exists
if ! [ -x "$(which aws)" ]; then
    echo "aws executable not found - exiting!"
    exit 1
fi

# source configuration if it exists
[ -f /etc/aws-ec2-ssh.conf ] && . /etc/aws-ec2-ssh.conf

# Assume a role before contacting AWS IAM to get users and keys.
# This can be used if you define your users in one AWS account, while the EC2
# instance you use this script runs in another.
: ${ASSUMEROLE:=""}

if [[ ! -z "${ASSUMEROLE}" ]]
then
  STSCredentials=$(aws sts assume-role \
    --role-arn "${ASSUMEROLE}" \
    --role-session-name something \
    --query '[Credentials.SessionToken,Credentials.AccessKeyId,Credentials.SecretAccessKey]' \
    --output text)

  AWS_ACCESS_KEY_ID=$(echo "${STSCredentials}" | awk '{print $2}')
  AWS_SECRET_ACCESS_KEY=$(echo "${STSCredentials}" | awk '{print $3}')
  AWS_SESSION_TOKEN=$(echo "${STSCredentials}" | awk '{print $1}')
  AWS_SECURITY_TOKEN=$(echo "${STSCredentials}" | awk '{print $1}')
  export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN AWS_SECURITY_TOKEN
fi

UnsaveUserName="$1"
UnsaveUserName=${UnsaveUserName//"_plus_"/"+"}
UnsaveUserName=${UnsaveUserName//"_equal_"/"="}
UnsaveUserName=${UnsaveUserName//"_comma_"/","}
UnsaveUserName=${UnsaveUserName//"_at_"/"@"}


# if cache keys is enabled, try to fetch the key locally first
USER_KEY_DIR="/opt/aws-ec2-ssh/cached-keys"
mkdir -p ${USER_KEY_DIR}
USER_KEYFILE="${USER_KEY_DIR}/key-${UnsaveUserName}"
if [[ -n ${CACHE_KEYS} ]] && [[ "1" == "${CACHE_KEYS}" ]]; then
  if [[ -f ${USER_KEYFILE} ]]; then
    cat "${USER_KEYFILE}"
    exit
  fi
fi
aws iam list-ssh-public-keys --user-name "$UnsaveUserName" --query "SSHPublicKeys[?Status == 'Active'].[SSHPublicKeyId]" --output text | while read -r KeyId; do
  KEY_OUTPUT=$(aws iam get-ssh-public-key --user-name "$UnsaveUserName" --ssh-public-key-id "$KeyId" --encoding SSH --query "SSHPublicKey.SSHPublicKeyBody" --output text)
  KEY_RESULT=$?
  if [[ -n ${CACHE_KEYS} ]] && [[ "1" == "${CACHE_KEYS}" ]] && [[ "0" == "${KEY_RESULT}" ]]; then
    echo "${KEY_OUTPUT}" >> "${USER_KEYFILE}"
  fi
  echo "${KEY_OUTPUT}"
done
