#!/bin/sh

qb_version="4.2.1" # 改：qBit的版本号，共三位数字
qb_username="用户名" # 改：qBit WebUI的登录用户名
qb_password="密码" # 改：qBit WebUI的登录密码
qb_web_url="http://localhost:8080" # 改：qBit WebUI的登录地址
log_dir="${HOME}/log/qBit-rclone-TagUploader" # 改：此脚本的日志保存的路径

unfinished_tag=("待上传-BG" "待上传-BG2") # 请自行添加此Tag至qBittorrent中
rclone_dest=("BG:/Upload" "BG2:/") # rclone上传目录；挂载名称参考rclone config中的name字段；格式为"XX:FOLDER"
rclone_parallel="32" # rclone上传线程 默认4

uploading_tag="上传中"
finished_tag="已上传"
noupload_tag="上传失败"

version=$(echo ${qb_version} | grep -P -o "([0-9]\.){2}[0-9]" | sed s/\\.//g)
timePat=`date +'%Y-%m-%d %H:%M:%S'`  # 时间计算方案


if [ ! -d ${log_dir} ]
then
	mkdir -p ${log_dir}
fi

function qb_login(){
	if [ ${version} -gt 404 ]
	then
		qb_v="1"
		cookie=$(curl -s -i --header "Referer: ${qb_web_url}" --data "username=${qb_username}&password=${qb_password}" "${qb_web_url}/api/v2/auth/login" | grep -P -o 'SID=\S{32}')
		if [ -n ${cookie} ]
		then
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] 登录成功！cookie:${cookie}" 

		else
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] 登录失败！" 
		fi
	elif [[ ${version} -le 404 && ${version} -ge 320 ]]
	then
		qb_v="2"
		cookie=$(curl -s -i --header "Referer: ${qb_web_url}" --data "username=${qb_username}&password=${qb_password}" "${qb_web_url}/login" | grep -P -o 'SID=\S{32}')
		if [ -n ${cookie} ]
		then
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] 登录成功！cookie:${cookie}" 
		else
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] 登录失败" 
		fi
	elif [[ ${version} -ge 310 && ${version} -lt 320 ]]
	then
		qb_v="3"
		echo "qBittorrent版本过旧"
		exit
	else
		qb_v="0"
		exit
	fi
}

function qb_remove_tag(){
	file_hash=$1
	fromTag=$2
	res_remove="0"
	
	# 这里是添加某些tag的方法
	trys=0
	until [[ $try -gt 3 ]]
	do
		if [ $res_remove != "200" ]
		then
			res_remove=$(curl -sL -w "%{http_code}" -X POST -d "hashes=${file_hash}&tags=${fromTag}" "${qb_web_url}/api/v2/torrents/removeTags" --cookie "${cookie}")
			let trys++
			if [[ ${trys} -gt 1 ]]
			then
				qb_login
			fi
			if [[ ${trys} -gt 3 ]]
			then
				echo "![$(date '+%Y-%m-%d %H:%M:%S')] Tag删除失败'${fromTag}' - ${file_hash}"
				echo "![$(date '+%Y-%m-%d %H:%M:%S')] Tag删除失败'${fromTag}' - ${file_hash}" >> ${log_dir}/qb.log
			fi
		else
			break
		fi
	done
	
	echo $res_remove
	
	if [[ ${res_remove} == "200" ]]
	then
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tag已删除'${fromTag}' - ${file_hash}"
	fi
}

function qb_add_tag(){
	file_hash=$1
	toTag=$2
	res_add="0"
	
	# 这里是添加某些tag的方法
	trys=0
	until [[ $try -gt 3 ]]
	do
		if [ $res_add != "200" ]
		then
			res_add=$(curl -sL -w "%{http_code}" -X POST -d "hashes=${file_hash}&tags=${toTag}" "${qb_web_url}/api/v2/torrents/addTags" --cookie "${cookie}")
			let trys++
			if [[ ${trys} -gt 1 ]]
			then
				qb_login
			fi
			if [[ ${trys} -gt 3 ]]
			then
				echo "![$(date '+%Y-%m-%d %H:%M:%S')] Tag添加失败'${toTag}' - ${file_hash}"
				echo "![$(date '+%Y-%m-%d %H:%M:%S')] Tag添加失败'${toTag}' - ${file_hash}" >> ${log_dir}/qb.log
			fi
		else
			break
		fi
	done
	
	echo $res_add
	
	if [[ ${res_add} == "200" ]]
	then
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tag已添加'${toTag}' - ${file_hash}"
	fi
}

# 先移除指定tag，后增加自己的tag
function qb_set_category(){
	file_hash=$1
	toTag=$2
	if [ ${qb_v} == "1" ]
	then
		curl -s -X POST -d "hashes=${file_hash}&category=${toTag}" "${qb_web_url}/api/v2/torrents/setCategory" --cookie ${cookie}
	elif [ ${qb_v} == "2" ]
	then
		curl -s -X POST -d "hashes=${file_hash}&category=${toTag}" "${qb_web_url}/command/setCategory" --cookie ${cookie}
	fi
}

function rclone_copy(){
	torrent_name=$1
	torrent_hash=$2
	torrent_path=$3
	n=$4

	# 这里执行上传程序
	if [ -f "${torrent_path}" ]
	then
		root_folder=$(echo $torrent_path | awk -F '/' '{print $NF}')
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 类型：文件 - ${root_folder}"
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 类型：文件 - ${root_folder}" >> ${log_dir}/qb.log
		type="file"
		
	elif [ -d "${torrent_path}" ]
	then
		root_folder=$(echo $torrent_path | awk -F '/' '{print $NF}')
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 类型：目录 - ${root_folder}"
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 类型：目录 - ${root_folder}" >> ${log_dir}/qb.log
		type="dir"
		
	else
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 未知类型，取消上传 - ${torrent_path}"
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 未知类型，取消上传 - ${torrent_path}" >> ${log_dir}/qb.log
		
		# tag = 不上传
		if [ ${qb_v} == "1" ]
		then
			qb_add_tag ${torrent_hash} ${noupload_tag}
		elif [ ${qb_v} == "2" ]
		then
			qb_set_category ${torrent_hash} ${noupload_tag}
		fi
		
		return
	fi
	
	# tag = 上传中
	if [ ${qb_v} == "1" ]
	then
		qb_add_tag ${torrent_hash} ${uploading_tag}
	elif [ ${qb_v} == "2" ]
	then
		qb_set_category ${torrent_hash} ${uploading_tag}
	fi
	
	
	
	# 执行上传
	start_seconds=$(date --date="$timePat" +%s);
	
	if [ ${type} == "file" ]
	then # 这里是rclone上传的方法
		rclone_copy_cmd=$(rclone -v copy --transfers ${rclone_parallel} "${torrent_path}" "${rclone_dest[n]}"/)
		status=$?
	elif [ ${type} == "dir" ]
	then
		rclone_copy_cmd=$(rclone -v copy --transfers ${rclone_parallel} "${torrent_path}"/ "${rclone_dest[n]}"/"${root_folder}"/)
		status=$?
	fi
	
	end_seconds=$(date --date="$timePat" +%s);
	use_seconds=$((end_seconds-start_seconds));
	use_min=$((use_seconds/60));
	use_sec=$((use_seconds%60));
	
	if [[ status -eq 0 ]]
	then
		# tag = 已上传
		if [ ${qb_v} == "1" ]
		then
			qb_add_tag ${torrent_hash} ${finished_tag}
			qb_remove_tag ${torrent_hash} ${uploading_tag}
		elif [ ${qb_v} == "2" ]
		then
			qb_set_category ${torrent_hash} ${finished_tag}
		fi
		
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 上传完成-用时:${use_min}分${use_sec}秒 - ${rclone_dest[n]} - ${root_folder}"
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 上传完成-用时:${use_min}分${use_sec}秒 - ${rclone_dest[n]} - ${root_folder}" >> ${log_dir}/qb.log
	else
		# tag = 不上传
		if [ ${qb_v} == "1" ]
		then
			qb_add_tag ${torrent_hash} ${noupload_tag}
		elif [ ${qb_v} == "2" ]
		then
			qb_set_category ${torrent_hash} ${noupload_tag}
		fi
		
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误-用时:${use_min}分${use_sec}秒"
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 错误-用时:${use_min}分${use_sec}秒}" >> ${log_dir}/qb.log
	fi

	
	echo -e >> ${log_dir}/qb.log
}

function file_lock(){
	$(touch qbup.lock)
}
function can_go_lock(){
	lockStatus=$(ls | grep qbup.lock)
	if [ -z "${lockStatus}" ]
	then
		noLock="1"
		return
	fi
	noLock="0"
}
function file_unlock(){
	$(rm -rf qbup.lock)
}

function doUpload(){
	torrentInfo=$1
	i=$2
	n=$3
	
	# IFS保存，因为名字中可能出现多个空格
	OLD_IFS=$IFS
	IFS="\n"
	
	torrent_name=$(echo "${torrentInfo}" | jq ".[$i] | .name" | sed s/\"//g)
	torrent_hash=$(echo "${torrentInfo}" | jq ".[$i] | .hash" | sed s/\"//g)
	torrent_path=$(echo "${torrentInfo}" | jq ".[$i] | .content_path" | sed s/\"//g)
	
	IFS=$OLD_IFS

	can_go_lock
	if [[ ${noLock} == "1" ]] # 厕所门能开
	then
		file_lock # 锁上厕所门
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始上传-${torrent_name}"
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始上传-${torrent_name}" >> ${log_dir}/qb.log
		rclone_copy "${torrent_name}" "${torrent_hash}" "${torrent_path}" $n
	else
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 已有程序在上传，退出"
		exit # 打不开门，换个时间来
	fi
	file_unlock # 打开厕所门，出去
}

# 每次只查询一条数据，！！上传一条数据！！
function qb_get_status(){
	qb_login
	if [ ${qb_v} == "1" ]
	then
		for ((n=0;n<${#unfinished_tag[@]};n++))
		do
			torrentInfo=$(curl -s "${qb_web_url}/api/v2/torrents/info?filter=completed&category=${unfinished_tag[n]}&sort=added_on" --cookie "${cookie}")
			completed_torrents_num=$(echo ${torrentInfo} | jq 'length')
			echo ${unfinished_tag[n]}":"${rclone_dest[n]}":任务数:"${completed_torrents_num}
			for((i=0;i<${completed_torrents_num};i++));
			do
				tags=$(echo ${torrentInfo} | jq ".[$i] | .tags")
				if [[ $tags =~ $uploading_tag ]] || [[ $tags =~ $finished_tag ]] || [[ $tags =~ $noupload_tag ]]
				then
					echo "包含tag"
					continue
				else
					echo "准备上传：$(echo "${torrentInfo}" | jq ".[$i] | .name" | sed s/\"//g)"
					doUpload "${torrentInfo}" ${i} ${n}
					# 每次只上传一个数据，否则的话，可能会导致多线程的争用问题
					break
				fi
			done
		done
	elif [ ${qb_v} == "2" ]
	then
		torrentInfo=$(curl -s "${qb_web_url}/query/torrents?filter=completed&tag=${unfinished_tag}" --cookie "${cookie}")
		completed_torrents_num=$(echo ${torrentInfo} | jq 'length')
		echo "待上传标签任务数："${completed_torrents_num}
		for((i=0;i<${completed_torrents_num};i++));
		do
			curtag=$(echo ${torrentInfo} | jq ".[$i] | .category" | sed s/\"//g)
			if [ -z "${curtag}" ]
			then
				curtag="null"
			fi

			if [ ${curtag} == "${unfinished_tag}" ]
			then
				doUpload "${torrentInfo}" ${i}
				# 每次只上传一个数据，否则的话，可能会导致多线程的争用问题
				break
			fi
		done
	else
		echo "获取错误"
		echo "qb_v=${qb_v}"
	fi
}

qb_get_status
