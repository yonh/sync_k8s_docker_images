#!/bin/bash

set -e

#### version 0.0.1(190706)

require_cmds="docker jq"
for cmd in $require_cmds ; do
  command -v $cmd >/dev/null 2>&1 || { echo "can not found \"$cmd\", please check" >&2; exit 1; }
done

images=(
k8s.gcr.io/kube-apiserver
k8s.gcr.io/kube-controller-manager
k8s.gcr.io/kube-scheduler
k8s.gcr.io/kube-proxy
k8s.gcr.io/pause
k8s.gcr.io/etcd
k8s.gcr.io/coredns
k8s.gcr.io/kubernetes-dashboard
)

mkdir -p k8s.gcr.io
mkdir -p hub.docker.com
for image in ${images[@]} ; do
    image_name=${image:11}

    image_json_file="k8s.gcr.io/${image_name}.json"
    curl -s -o $image_json_file https://gcr.io/v2/google-containers/${image_name}/tags/list
    cat ${image_json_file}|jq -e . >/dev/null

    image_json_file="hub.docker.com/${image_name}.json"
    curl -s -o ${image_json_file} https://hub.docker.com/v2/repositories/${DOCKER_USERNAME}/${image_name}/tags/
    cat ${image_json_file}|jq -e . >/dev/null


    k8s_image_json_file="k8s.gcr.io/${image_name}.json"
    hub_image_json_file="hub.docker.com/${image_name}.json"
    
    regex='^(v?[\.0-9]+)$'
    for tag in `cat ${k8s_image_json_file}|jq -r '.tags|.[]'`;
    do
      echo "tag: $tag"
    	# $tag => k8s tag
      if [[ $tag =~ $regex ]]; then
	    #echo $image_name/"${BASH_REMATCH[1]}"
	    v=${BASH_REMATCH[1]}
	    
	    exists=`cat hub.docker.com/${image_name}.json|jq -r ".results[]|.name|select(. == \"$v\")|."`
            echo "exists: $exists"
	    if [[ "$exists" == "" ]]; then
		echo empty
	    	#docker pull $image:$tag
	    	#docker tag $image:$tag ${DOCKER_USERNAME}/${image_name}:${tag}
	    	#docker push ${DOCKER_USERNAME}/${image_name}:${tag}
	    	#docker rmi ${DOCKER_USERNAME}/${image_name}:${tag} $image:$tag
	    fi
	  fi
	done
done

