#!/bin/bash
set -e
#set -euxo pipefail

#### version 0.0.1 (190706)
#### version 0.0.2 (190724)
##> 修复 Docker Hub 镜像只获取第一页的数据导致大多数镜像每次跑脚本都重复提交的问题
##> 完善bash脚本检查(bash 版本小于4.0),提示版本过低警告, 其实脚本是支持3的
#### version 0.0.3 (210413)
##> 替换k8s镜像版本获取API地址,旧版地址返回内容不全且没有更新镜像


#### plans
#### version 0.0.4
##> 支持多 registry push 方案



#### 脚本作用
## 本脚本是用来同步使用kubeadm 安装k8s 时需要的镜像（使得国内可以免翻墙使用 kubeadm 安装 k8s）, 嫌麻烦可以使用我的 docker hub 同步的镜像，不必自己同步

#### 软件依赖
## bash,docker,jq
## apt update && apt install -y docker.io jq

#### 使用方式
## 修改本脚本下的 Docker Hub 的账户密码，或设置环境变量 DOCKER_USERNAME, DOCKER_PASSWORD
## bash main.sh


## 由于脚本预计跑在 TravisCi,所以密码使用环境变量配置起来，如果是跑在自己的服务器，可以把注释解开
DOCKER_USERNAME=""   ##
DOCKER_PASSWORD=""   ##
echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin ##


function version_gt() { test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"; }

if version_gt "4.0.0" $BASH_VERSION ; then
     echo "[warning] your bash version now is 3.0, it less then 4.0.0, we suggest you update version to 4.0.0 or higher"
#     exit 1
fi


require_cmds="docker jq"
for cmd in $require_cmds ; do
  command -v $cmd >/dev/null 2>&1 || { echo "Unknown command \"$cmd\", please try install the package first." >&2; exit 1; }
done

## 需要同步的镜像
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

	## 获取image name,删掉 k8s.gcr.io/ 部分
    image_name=${image:11}

    #### 下载镜像信息描述文件 ##
    image_json_file="k8s.gcr.io/${image_name}.json"
    # curl -s -o $image_json_file https://gcr.io/v2/google-containers/${image_name}/tags/list
    curl -s -o $image_json_file https://k8s.gcr.io/v2/${image_name}/tags/list
    ## 检查 json格式是否正常
    cat ${image_json_file}|jq -e . >/dev/null

    # docker hub 不是一次性给出所有数据，需要分页查询,所以这里做特殊处理
    image_json_file="hub.docker.com/${image_name}.json"
#    curl -s -o ${image_json_file} https://hub.docker.com/v2/repositories/${DOCKER_USERNAME}/${image_name}/tags/?page_size=100
#    ## 检查 json格式是否正常
#    cat ${image_json_file}|jq -e . >/dev/null
    docker_hub_tags_file="/tmp/tags"

    ## docker hub 的接口一次最多获取100条记录，所以需要分页获取，这里就将获取到的结果然后提取 tag 到 tags 文件里面去
    url="https://hub.docker.com/v2/repositories/${DOCKER_USERNAME}/${image_name}/tags/?page=1&page_size=100"
    echo "" > $docker_hub_tags_file
    while true ;
    do
        if [ "$url" != "null" ] && [ "$url" != "" ] ; then

            curl -s -o $image_json_file $url
            cat ${image_json_file}|jq -e . >/dev/null

            ## 可能镜像么有上传过 docker hub，此时会返回对象找不到
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

    #### 下载镜像信息描述文件 [END]###


    #### 找出未上传的镜像 ##
    ## 找出符合的版本号的tag,这里不同步其他零散的包，只同步主版本号的包,如需其他，请修改匹配正则表达式
    k8s_image_json_file="k8s.gcr.io/${image_name}.json"
    hub_image_json_file="hub.docker.com/${image_name}.json"
    
    regex='^(v?[\.0-9\-]+)$'
    for tag in `cat ${k8s_image_json_file}|jq -r '.tags|.[]'`;
    do
    	## $tag => k8s tag
      if [[ $tag =~ $regex ]]; then
	    ## echo $image_name/"${BASH_REMATCH[1]}"
	    v=${BASH_REMATCH[1]}

	    ## 可能镜像么有上传过 docker hub，此时会返回对象找不到
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

