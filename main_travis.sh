#!/bin/bash
set -e






#DOCKER_USERNAME=""
#DOCKER_PASSWORD=""

require_cmds="docker jq"
for cmd in $require_cmds ; do
  command -v $cmd >/dev/null 2>&1 || { echo "Unknown command \"$cmd\", please try install the package first." >&2; exit 1; }
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
    curl -s -o ${image_json_file} https://hub.docker.com/v2/repositories/${DOCKER_USERNAME}/${image_name}/tags/?page_size=1000
    cat ${image_json_file}|jq -e . >/dev/null


    k8s_image_json_file="k8s.gcr.io/${image_name}.json"
    hub_image_json_file="hub.docker.com/${image_name}.json"
    
    regex='^(v?[\.0-9]+)$'
    for tag in `cat ${k8s_image_json_file}|jq -r '.tags|.[]'`;
    do
      if [[ $tag =~ $regex ]]; then
	    v=${BASH_REMATCH[1]}
	    
	    
        not=`cat a.json|jq -r '.detail'`

        if [[ "$not" = "Object not found" ]]; then
        	exists=""
        else
        	exists=`cat hub.docker.com/${image_name}.json|jq -r ".results[]|.name|select(. == \"$v\")|."`
        fi
	    
	    if [[ "$exists" == "" ]]; then
	    	docker pull $image:$tag
	    	docker tag $image:$tag ${DOCKER_USERNAME}/${image_name}:${tag}
	    	docker push ${DOCKER_USERNAME}/${image_name}:${tag}
	    	docker rmi ${DOCKER_USERNAME}/${image_name}:${tag} $image:$tag
	    fi
	  fi
	done
done

