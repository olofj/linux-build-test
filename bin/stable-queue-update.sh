#!/bin/bash

PATH=${PATH}:${HOME}/bin

echo "$(date): running"

BASE=${HOME}/work
LINUX=${BASE}/linux-stable

# The current directory is the stable-queue git directory.
QCLONE=$(pwd)

if [ $# -gt 0 ]
then
	releases=($*)
else
	releases=(3.10 3.14 3.18)
fi

do_import()
{
	release=$1
	qdir=${QCLONE}/queue-${release}
	branch=linux-${release}.y
	qbranch=linux-${release}.y.queue
	tbranch=${qbranch}.test
	ref=origin/${branch}

	if [ "${release}" = "3.4" ]
	then
		qdir=${QCLONE}/patches
	else
		qdir=${QCLONE}/queue-${release}
	fi

	echo "Importing ${release}"

	cd ${LINUX}

	git rebase --abort >/dev/null 2>&1
	git clean -f -d -q -x
	git checkout master

	git fetch --all
	git pull

	git show-branch ${branch}
	if [ $? -ne 0 ]
	then
		git checkout -b ${branch} ${ref}
	else
		git checkout ${branch}
		git reset --hard origin/${branch}
	fi

	# reference branch exists locally and is up to date

	git show-branch ${qbranch}
	if [ $? -ne 0 ]
	then
		git checkout -b ${qbranch} ${ref}
	else
		git checkout ${qbranch}
	fi

	# queue branch exists locally.

	if [ ! -d ${qdir} ]
	then
		# We are done. Reset qbranch to point to parent.
		# This ensures that we catch release updates.
		echo "${release}: No pending patches. Cleaning up."
		git reset --hard ${branch}
		git clean -f -d -q
		git push --force origin ${branch} ${qbranch}
		return 0
	fi

	# Create clean test branch as child of reference branch

	git branch -D ${tbranch} >/dev/null 2>&1
	git checkout -b ${tbranch} ${branch}

	# echo ready for import

	git quiltimport --patches=${qdir} --author="Anonymous <unknown@nowhere.net>"
	if [ $? -ne 0 ]
	then
		echo "${release}: git quiltimport failed - skipping"
		git clean -f -d -q
		return 0
	fi

	git diff --exit-code --summary ${qbranch}
	if [ $? -ne 0 ]
	then
		echo "${release}: Queue branch changes detected. Updating."
		# git branch -D ${qbranch}
		git branch -M ${qbranch}
	else
		echo "${release}: Queue branch unchanged. Done."
	fi
	# Push any changes to local repository.
	git push --force origin ${branch} ${qbranch}
}

do_clone()
{
	REPO=$1
	ORIGIN=$2

	mkdir -p ${BASE}
	cd ${BASE}
	if [ ! -d ${REPO} ]
	then
		echo "Cloning ${REPO} ..."
		git clone ${ORIGIN}
	else
		echo "Updating ${REPO} ..."
		cd ${REPO}
		git fetch
		git rebase --abort 2>/dev/null
		git clean -f -d -q
		git checkout master
		git pull
	fi
}

# First update tracking branch from origin

do_clone linux-stable git://server.roeck-us.net/git/linux-stable.git

for rel in ${releases[*]}
do
	do_import ${rel}
done

echo "$(date): complete"
