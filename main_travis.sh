#!/bin/bash
set -e
#set -euxo pipefail












function version_gt() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"; }

if version_gt "4.0.0" $BASH_VERSION ; then
     echo "[warning] your bash version now is 3.0, it less then 4.0.0, we suggest you update version to 4.0.0 or higher"
#     exit 1
fi


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
k8s.gcr.io/kubernetes-dashboard-amd64
)


mkdir -p k8s.gcr.io
mkdir -p hub.docker.com
for image in ${images[@]} ;
do

    image_name=${image:11}

    image_json_file="k8s.gcr.io/${image_name}.json"
    # curl -s -o $image_json_file https://gcr.io/v2/google-containers/${image_name}/tags/list
    curl -s -o $image_json_file https://k8s.gcr.io/v2/${image_name}/tags/list
    cat ${image_json_file}|jq -e . >/dev/null

    # docker hub 不是一次性给出所有数据，需要分页查询,所以这里做特殊处理
    image_json_file="hub.docker.com/${image_name}.json"
#    curl -s -o ${image_json_file} https://hub.docker.com/v2/repositories/${DOCKER_USERNAME}/${image_name}/tags/?page_size=100
#    cat ${image_json_file}|jq -e . >/dev/null
    docker_hub_tags_file="/tmp/tags"

    url="https://hub.docker.com/v2/repositories/${DOCKER_USERNAME}/${image_name}/tags/?page=1&page_size=100"
    echo "" > $docker_hub_tags_file
    while true ;
    do
        if [ "$url" != "null" ] && [ "$url" != "" ] ; then

            curl -s -o $image_json_file $url
            cat ${image_json_file}|jq -e . >/dev/null

            not=`cat $image_json_file|jq -r '.detail'`
            if [[ "$not" == "Object not found" ]]; then
                break
            fi

            cat $image_json_file|jq -r '.results[].name' >> $docker_hub_tags_file
            url=`cat $image_json_file | jq -r '.next'`
        else
            break
        fi
    done



    k8s_image_json_file="k8s.gcr.io/${image_name}.json"
    hub_image_json_file="hub.docker.com/${image_name}.json"
    
    regex='^(v?[\.0-9]+)$'
    for tag in `cat ${k8s_image_json_file}|jq -r '.tags|.[]'`;
    do
      if [[ $tag =~ $regex ]]; then
	    v=${BASH_REMATCH[1]}

        #not=`cat hub.docker.com/${image_name}.json|jq -r '.detail'`

        exists=`cat $docker_hub_tags_file |grep $v\$ || true`

#        if [[ "$not" = "Object not found" ]]; then
#        	exists=""
#        else
#        	# 取出没有上传到 docker hub 的镜像 tags
#        	exists=`cat hub.docker.com/${image_name}.json|jq -r ".results[]|.name|select(. == \"$v\")|."`
#        fi

	    if [[ "$exists" == "" ]]; then
	    	docker pull $image:$tag
	    	docker tag $image:$tag ${DOCKER_USERNAME}/${image_name}:${tag}
	    	docker push ${DOCKER_USERNAME}/${image_name}:${tag}
	    	docker rmi ${DOCKER_USERNAME}/${image_name}:${tag} $image:$tag
	    fi
	  fi
	done
done

