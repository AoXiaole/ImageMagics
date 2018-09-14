
#该文件为公共sh，供其他shell引用

# TODO: 路径待定
file_configure="${g_sh_path}/configure.ini"
#DEBUG=1
#INFO=2
#WARNING=3
#ERR=4

declare -A level_map=()
level_map["DEBUG"]=1
level_map["INFO"]=2
level_map["WARNING"]=3
level_map["ERR"]=4
level_map["FATAL"]=5

#通过字符串得到在 configure 中对应的值
# $1 : key
# $2 : 默认值
function getValueFromConfig()
{
    local value=`grep  "^[[:blank:]]*$1=" ${file_configure}`
    value=${value##*=}
    value=${value%%#*}
    
    echo ${value:-$2}
}

log_dir=$(getValueFromConfig "log_dir" "${g_sh_path}/log/convert")
logLevel=$(getValueFromConfig "logLevel" "DEBUG")

#打印日志，格式为：log LEVEL "msg"
function log()
{
    if [ $# -lt 2 ];then
        echo "log param error"
        return 1
    fi
    local outLogFile=${log_dir}
    
    local outLogDir=$(dirname ${outLogFile})
    local level=$1
    local str=$2
    local ls_value
    local file_size
    local time_

    if [ ! -d ${outLogDir} ];then
        mkdir -p ${outLogDir}
    fi
    
    if [ -z "${level_map[${level}]}" ] || [ ${level_map[${level}]} -ge ${level_map[${logLevel}]} ];then
        
        time_=`date "+%Y-%m-%d %H:%M:%S"`
        echo "[${time_}] [${level}] ${str}" >> ${outLogFile}.log
        
        ls_value=`ls -l ${outLogFile}.log 2>&1`
        if [ $? -ne 0 ];then
            return
        fi
        
        file_size=`echo "${ls_value}" | head -1 | awk '{print int($5/1024/1024)}'`
    
        if [ ! -z "${file_size}" ] && [ ${file_size} -ge 20 ];then
            local log_name="${outLogFile}.$(date +%Y%m%d%H%M%S)"
            mv ${outLogFile}.log ${log_name}.log
        fi
    fi

}
