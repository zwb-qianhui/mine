#!/bin/bash
#本脚本的功能为在人工修复了后端故障服务器后,将其添加进入MHA集群
#运行前提是MHA集群配置正确,并且后端故障服务器修复成功
 
#####本脚本运行需要进行的准备工作与注意事项

#由于MHA集群故障切换时会对主配置文件进行修改,故而在使用此脚本前,请将完整的app1.cnf文件备份为app1.true存放于相同路径
#workdir存储mha工作路径,也是本脚本唯一需要手动输入的参数
#此脚本运行时会在运行时所在的路径创建临时文件[1-3].txt,如果存在这些文件,可能出现错误
workdir=/etc/mha

#####

#app存储mha主配置文件路径
app=$workdir/app1.cnf
#mhamon为监控用户名
#mhamonpw为监控用户密码
mhamon=`awk -F= '/^user=/{print $2}' $workdir/app1.true`
mhamonpw=`awk -F= '/^password=/{print $2}' $workdir/app1.true`
#repluser为数据同步用户名
#repluserpw为数据同步用户密码
repluser=`awk -F= '/^repl_user=/{print $2}' $workdir/app1.true`
repluserpw=`awk -F= '/^repl_password=/{print $2}' $workdir/app1.true`
#从app1.true中把关键信息查找出来存放在1.txt
awk -F= 'BEGIN{i=0}/\[server[0-9][0-9]*/{i++;j[i]=$1}/candidate_master/{k[i]=$2}/hostname/{l[i]=$2}/port=/{m[i]=$2}END{for(i in j){print j[i],k[i],l[i],m[i]}}'	$workdir/app1.true > 1.txt
#num为后台服务器总个数
num=`awk "END{print NR}" 1.txt`
#ip存储所有后台服务器ip
#stat为中间量
for i in `seq $num`
do
        stat[$i]=0
	ip[$i]=`awk  "NR==$i" 1.txt | awk '{print $3}'`
done
#统计正常库ip
tjzckip(){
masterha_check_repl --conf=$app &> 2.txt
zt=`sed -n '$p' 2.txt`
zt=${zt##*Health }
zt=${zt// /}
health='isOK.'
if [ $zt != $health ];then
	echo '健康状态出错' && exit
fi
masterip=`grep '(current master)' 2.txt`
masterip=${masterip%%(*}
slave=`awk '/\+--/' 2.txt`
slave=${slave#*+--}
slaveip=()
i=1
z=`echo $slave | awk '{print $1}'`
while [ ! -z $z ]
do	
	slaveip[$i]=${slave%%(*}
	slave=${slave#*)}
	slave=${slave#*+--}
	z=`echo $slave | awk '{print $1}'`
	let i++
done
rm -rf 2.txt
}
#找出遗失的ip
zccwip(){
for j in `seq $[i-1]`
do
	csip=${slaveip[$j]}
	for k in `seq $num`
	do
		if [ ${ip[$k]} == $csip ];then
			let stat[$k]++
		fi
	done
done
for k in `seq $num`
do
	if [ ${ip[$k]} == $masterip ];then
		let stat[$k]++
	fi
done
}
#获取主库日志,3.txt为临时文件,log存储日志名,pos存储偏移量
hq(){
mysql -h$masterip -u$mhamon -p$mhamonpw -e "show master status" &> 3.txt
file=`awk 'NR==3{print $1}' 3.txt`
pos=`awk 'NR==3{print $2}' 3.txt`
rm -rf 3.txt
}
#在恢复的主机生成主从结构,并在管理节点将其添加到主配置文件
zc(){
for k in `seq $num`
do
	if [ ${stat[$k]} -eq 0 ];then
		server=`awk "NR==$k" 1.txt | awk '{print $1}'`
		candi=`awk "NR==$k" 1.txt | awk '{print $2}'`
		port=`awk "NR==$k" 1.txt | awk '{print $4}'`
		mysql -h${ip[$k]} -u$mhamon -p$mhamonpw -e "change master to master_host=\"$masterip\",master_user=\"$repluser\",master_password=\"$repluserpw\",master_log_file=\"$file\",master_log_pos=$pos;start slave;"
		echo -e "\n$server\ncandidate_master=$candi\nhostname=${ip[$k]}\nport=$port" >> $app
	fi
done
rm -rf 1.txt
}
main (){
tjzckip
zccwip
hq
zc
}
main
