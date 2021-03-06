#!/bin/bash

min_vbox_ver="5.1.10"
min_vagrant_ver="1.9.0"
min_packer_ver="0.10.0"
min_vagrantreload_ver="0.0.1"
packer_bin="packer"
packer_build_path="packer/builds"

case "$1" in
    ubuntu1404)  echo "building ubuntu 1404"
                 os_full="ubuntu_1404"
                 os_short="ub1404"
                 ;;

    windows2008) echo "building windows 2008"
                 os_full="windows_2008_r2"
                 os_short="win2k8"
                 ;;

    *)           echo "Invalid OS. Valid options are 'ubuntu1404' and 'windows2008'"
                 exit 1
                 ;;
esac

box_version=$(grep \"box_version\": packer/templates/$os_full.json | grep -Eow "[0-9]\.[0-9]\.[0-9]+")

function compare_versions {
    actual_version=$1
    expected_version=$2
    exact_match=$3

    if $exact_match; then
        if [ "$actual_version" == "$expected_version" ]; then
            return 0
        else
            return 1
        fi
    fi

    IFS='.' read -ra actual_version <<< "$actual_version"
    IFS='.' read -ra expected_version <<< "$expected_version"

    for ((i=0; i < ${#expected_version[@]}; i++))
    do
        if [[ ${actual_version[$i]} -gt ${expected_version[$i]} ]]; then
            return 0
        fi

        if [[ ${actual_version[$i]} -lt ${expected_version[$i]} ]]; then
            return 1
        fi
    done
    return 0
}

# Conditional for platform specific version checks. Some of these might seem redundant since
# there might not be anything actively broken in the dependent software. Keeping it around as
# version upgrades could break things on specific platforms.
if [ $(uname) = "Darwin" ]; then
    vagrant_exact_match=false
elif [ $(uname) = "Linux" ]; then
    vagrant_exact_match=false
    if (cat /etc/*-release | grep -q 'DISTRIB_ID=Arch')|(cat /etc/os-release | grep -Pq 'ID=(arch|"antergos")'); then
        packer_bin="packer-io"
    fi
fi

if [ -x "$(which VBoxManage)" ] ; then
    current_vbox_ver=$(VBoxManage -v | sed -e 's/r.*//g' -e 's/_.*//g')
    if compare_versions $current_vbox_ver $min_vbox_ver false; then
        echo "Compatible version of VirtualBox found."
    else
        echo "A compatible version of VirtualBox was not found."
        echo "Current Version=[$current_vbox_ver], Minimum Version=[$min_vbox_ver]"
        echo "Please download and install it from https://www.virtualbox.org/"
        exit 1
    fi
else
    echo "VirtualBox is not installed (or not added to the path)."
    echo "Please download and install it from https://www.virtualbox.org/"
    exit 1
fi

if compare_versions $($packer_bin -v) $min_packer_ver false; then
    echo "Compatible version of $packer_bin was found."
else
    packer_bin=packer
    if compare_versions $($packer_bin -v) $min_packer_ver false; then
        echo "Compatible version of $packer_bin was found."
    else
        echo "A compatible version of packer was not found. Please install from here: https://www.packer.io/downloads.html"
        exit 1
    fi
fi

if compare_versions $(vagrant -v | cut -d' ' -f2) $min_vagrant_ver $vagrant_exact_match; then
    echo 'Correct version of vagrant was found.'
else
    echo "A compatible version of vagrant was not found. Please download and install it from https://www.vagrantup.com/downloads.html."
    exit 1
fi

if compare_versions $(vagrant plugin list | grep 'vagrant-reload' | cut -d' ' -f2 | tr -d '(' | tr -d ')') $min_vagrantreload_ver false; then
    echo 'Compatible version of vagrant-reload plugin was found.'
else
    echo "A compatible version of vagrant-reload plugin was not found."
    echo "Attempting to install..."
    if vagrant plugin install vagrant-reload; then
        echo "Successfully installed the vagrant-reload plugin."
    else
        echo "There was an error installing the vagrant-reload plugin. Please see the above output for more information."
        exit 1
    fi
fi

echo "All requirements found. Proceeding..."

search_string="$os_full"_virtualbox_"$box_version"
if ls $packer_build_path | grep -q "$search_string"; then
    echo "It looks like the vagrant box already exists. Skipping the Packer build."
else
    echo "Building the Vagrant box..."
    if $packer_bin build --only=virtualbox-iso packer/templates/$os_full.json; then
        echo "Box successfully built by Packer."
    else
        echo "Error building the Vagrant box using Packer. Please check the output above for any error messages."
        exit 1
    fi
fi

echo "Attempting to add the box to Vagrant..."

if vagrant box list | grep -q metasploitable3-"$os_short"; then
    echo "metasploitable3-$os_short already found in Vagrant box repository. Skipping the addition to Vagrant."
    echo "NOTE: If you are having issues, try starting over by doing 'vagrant destroy' and then 'vagrant up'."
else
    if vagrant box add $packer_build_path/"$os_full"_virtualbox_"$box_version".box --name metasploitable3-$os_short; then
        echo "Box successfully added to Vagrant."
    else
        echo "Error adding box to Vagrant. See the above output for any error messages."
        exit 1
    fi
fi

echo "---------------------------------------------------------------------"
echo "SUCCESS: Run 'vagrant up' to provision and start metasploitable3."
echo "NOTE: The VM will need Internet access to provision properly."
