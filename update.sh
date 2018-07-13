#!/usr/bin/env bash

SCRIPT_PATH=/home/mason/esi-updater

LOCAL_REPO=$1
REMOTE_REPO=$2

ESI_SPEC_URL="https://esi.evetech.net/_latest/swagger.json"
SWAGGER_CODEGEN_CLI=${SCRIPT_PATH}/swagger-codegen-cli.jar

if [ -z $1 ] || [ -z $2 ]; then
	echo "Usage: updater.sh local remote" >&2;
	exit 1;
fi

if ! [ -x "$(command -v git)" ]; then
	echo "Error: git not found. exiting..." >&2;
	exit 1;
fi

if ! [ -x "$(command -v java)" ]; then
        echo "Error: java not found. exiting..." >&2;
        exit 1;
fi

# TODO: won't work if scripts runs from another path
if ! [ -e $SWAGGER_CODEGEN_CLI ]; then
        echo "Error: swagger-codegen-cli.jar not found. exiting..." >&2;
        exit 1;
fi

if ! [ -d $LOCAL_REPO ]; then
	echo "Creating directory: $LOCAL_REPO";
	mkdir -p $LOCAL_REPO;
fi

cd $LOCAL_REPO

eval `ssh-agent` &>> ${SCRIPT_PATH}/debug.log
ssh-add /home/mason/.ssh/git_esi_id_rsa &>> ${SCRIPT_PATH}/debug.log

# If .git already exists, assume it's the correct repository.
# This could probably backfire...
if ! [ -d ".git" ]; then
	# TODO: cloning with ssh gives RSA key fingerprint warning
	# NOTE: needs deploy key and ssh-agent
	git clone $REMOTE_REPO . &>> ${SCRIPT_PATH}/debug.log;
else
	git pull &>> ${SCRIPT_PATH}/debug.log
fi

LATEST_TAG=`git describe --abbrev=0 --tags`
OUR_VERSION=${LATEST_TAG//v} # remove leading "v"

echo "Fetching latest $ESI_SPEC_URL"
SWAGGER_JSON=`curl -s $ESI_SPEC_URL`
SPEC_VERSION_REGEX='"version":"\K\d\.\d\.\d'
SPEC_VERSION=`echo $SWAGGER_JSON | grep -oP $SPEC_VERSION_REGEX`

echo "Latest: $SPEC_VERSION - Current: $OUR_VERSION"

if [ "$OUR_VERSION" == "$SPEC_VERSION" ]; then
	echo "No new updates.  Exiting...";
	exit 0;
fi

echo "Building new version"
java -jar $SWAGGER_CODEGEN_CLI generate -i <(echo "$SWAGGER_JSON") -l go -c ${SCRIPT_PATH}/config.json  &>> ${SCRIPT_PATH}/debug.log

echo "Commiting and pushing changes to github"
git add . &>> ${SCRIPT_PATH}/debug.log
git commit -m "Release v$SPEC_VERSION" &>> ${SCRIPT_PATH}/debug.log
git tag -a "v$SPEC_VERSION" -m "release v$SPEC_VERSION" &>> ${SCRIPT_PATH}/debug.log
git push &>> ${SCRIPT_PATH}/debug.log
git push --tags &>> ${SCRIPT_PATH}/debug.log

eval `ssh-agent -k` &>> ${SCRIPT_PATH}/debug.log
