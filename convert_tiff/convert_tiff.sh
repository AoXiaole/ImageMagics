#!/bin/bash
# 运行环境需要安装 libreoffice，ImageMagics; 命令： yum install libreoffice libreoffice-headless ImageMagick -y
#
# $1 为源文件目录
# $2 转码源文件可以是一个列表，与‘，’ 分隔,不带路径
# $3 转码目标文件 , 带全路径
type convert > /dev/null 2>&1
if [ $? -ne 0 ];then
    yum install ImageMagick -y
fi
type libreoffice > /dev/null 2>&1
if [ $? -ne 0 ];then
    yum install libreoffice libreoffice-headless -y
fi

g_sh_path=$(cd `dirname $0`; pwd)
source ${g_sh_path}/common.sh

if [ $# -ne 3 ];then
    echo "input param error:\n"
#   echo "srcdir:$1"
	echo "fillist:$2"
#	echo "tifffile:$3"
    exit 1
fi

g_pid=$$
g_srcdir=$1
g_srcfilelist=${2//,/ }
g_tiffname=$3
g_tifflist=""
g_density=$(getValueFromConfig "density" "204x196")
g_size=$(getValueFromConfig "size" "1728x2156")
g_ret=0
g_value=""
g_watermark_flag=$(getValueFromConfig "watermark_flag" "0")
g_watermark_position=$(getValueFromConfig "watermark_position" "+700+1078")
g_watermark_string=$(getValueFromConfig "watermark_string" "hello world")

g_font_file=${g_sh_path}/msyh.ttf
#tmpdir 用于中间生成的文件 保存路径
g_tmp_dir=$(getValueFromConfig "tmp_dir" "/tmp")
g_tmp_pid_dir=${g_tmp_dir}/tmp_${g_pid}

if [ -f ${g_tiffname} ];then
    log DEBUG "${g_tiffname} have existed."
    exit 0
fi

g_tiffdir=$(dirname ${g_tiffname})
if [ ! -d ${g_tiffdir} ];then
    g_value=`mkdir -p ${g_tiffdir} 2>&1`
    g_ret=$?
    if [ ${g_ret} -ne 0 ];then
        log ERR "${g_value}"
        echo ${g_value}
        exit ${g_ret}
    fi 

fi

g_value=`mkdir -p ${g_tmp_pid_dir} 2>&1`
g_ret=$?
if [ ${g_ret} -ne 0 ];then
    log ERR "${g_value}"
    echo ${g_value}
    exit ${g_ret}
fi 

g_white_tiff=${g_tmp_pid_dir}/white_${g_density}_${g_size}.tiff

# 生成空白页
if [ ! -f ${g_white_tiff} ];then
    g_value=`convert -size ${g_size} -density ${g_density} -units PixelsPerInch -compress Fax -monochrome xc:none -threshold -1 ${g_white_tiff} 2>&1`
    g_ret=$?
    if [ ${g_ret} -ne 0 ];then
        log ERR "${g_value}"
		echo "convert white page failed"
        exit ${g_ret}
    fi 
fi

#获取 pdf文件的页数
function get_pdf_pages()
{
    local page=0
    page=`pdfinfo $1 | grep Pages | awk '{print $2}'`
    if [ $? -ne 0 ];then
        echo 0
        return 1
    fi
    echo ${page}
    return 0
}

# 不带后缀，不带路径的文件名
function get_filebasename()
{
    local filename=${1##*/}
    filename=${filename%.*}
    echo ${filename}
}

#doc，execl，ppt，txt 可以通过该函数转码为对应的pdf文件
#param：$1 需要转码的文件一个，全路径的;
#out： 成功返回 0， 输出 转码后的文件，全路径
function libreoffice_pdf()
{
    local srcfile
    local ret
    local value
    local tmp_base_name
    
    if [ $# -ne 1 ];then
        return 1
    fi
    
    srcfile=$1
    tmp_base_name=$(get_filebasename ${srcfile})
    # doc 转pdf 没有指定文件名
    value=`libreoffice  --invisible --convert-to pdf  --outdir ${g_tmp_pid_dir} ${srcfile} 2>&1`
    ret=$?
    if [ ${ret} -ne 0 ];then
        log ERR "${value}"
        return ${ret}
        
    else
        echo "${g_tmp_pid_dir}/${tmp_base_name}.pdf"
        log DEBUG "libreoffice ${srcfile} to ${g_tmp_pid_dir}/${tmp_base_name}.pdf success."
        return 0
    fi

}

# 将pdf 转为 tiff
#param：$1 需要转码的文件一个，全路径的
#out： 成功返回 0， 输出 转码后的文件，全路径
function convert_pdf_to_tiff()
{
    local tifflist=""
    local pages=0
    local i=0
    local pdffile
    local tmp_base_name     # 不带后缀，不带路径的文件名，用于生成jpeg和tiff的文件名
    local ret=0
    local value=""
    
    if [ $# -ne 1 ];then
        return 1
    fi
    
    pdffile=$1
    tmp_base_name=$(get_filebasename ${pdffile})
    
    pages=$(get_pdf_pages ${pdffile})
    if [ -z "${pages}" ];then
        log ERR "convert_pdf_to_tiff pages ${pdffile} is zero !"
        return 1
    fi
    #pdf 文件一页页的转为 jpeg，然后再转为tiff
    for((i=0;i<${pages};i++))
    do
        value=`convert -density ${g_density} -units PixelsPerInch -resize ${g_size} ${pdffile}[$i] -background white -flatten ${g_tmp_pid_dir}/${tmp_base_name}-${i}.jpeg 2>&1`
        ret=$?
        if [ ${ret} -ne 0 ];then
            log ERR "${value}"
            break
        fi
        
        value=`convert ${g_white_tiff} -compose atop ${g_tmp_pid_dir}/${tmp_base_name}-${i}.jpeg -composite ${g_tmp_pid_dir}/${tmp_base_name}-${i}.tiff 2>&1`
        ret=$?
        if [ ${ret} -ne 0 ];then
            log ERR "${value}"
            break
        fi        
        tifflist="${tifflist} ${tmp_base_name}-${i}.tiff"
    done
    
    local last_pwd=$(pwd)
    cd ${g_tmp_pid_dir}
    
    # 将 pdf 的tiff文件合并到一个 tiff
    value=`convert ${tifflist} ${tmp_base_name}.tiff 2>&1`
    ret=$?
    cd ${last_pwd}
    if [ ${ret} -ne 0 ];then
        log ERR "${value}"
    else
        echo "${g_tmp_pid_dir}/${tmp_base_name}.tiff"     # 输出全路径 的tiff文件
        log DEBUG "convert_pdf_to_tiff ${pdffile} to ${g_tmp_pid_dir}/${tmp_base_name}.tiff success."
    fi
    
    return ${ret} 
}

# 将doc/execl/ppt/txt 转为 tiff
#param：$1 需要转码的文件一个，全路径的
#out： 成功返回 0， 输出 转码后的文件，全路径
function convert_office_to_tiff()
{
    local ret=0
    local value=""
    local srcfile=""
    local pdffile=""
    
    if [ $# -ne 1 ];then
        return 1
    fi
    srcfile=$1
    #先转为pdf
    value=$(libreoffice_pdf ${srcfile})
    ret=$?
    if [ ${ret} -ne 0 ];then
        log ERR "libreoffice_pdf ${srcfile} failed !"
        return ${ret}
    fi

    pdffile=${value}
    
    #再将pdf转tiff
    value=$(convert_pdf_to_tiff ${pdffile})
    ret=$?
    if [ ${ret} -ne 0 ];then
        log ERR "convert_pdf_to_tiff ${pdffile} failed !"
        return ${ret}
    fi
    
    log DEBUG "convert_office_to_tiff ${srcfile} to ${value} success."
    echo ${value}
    return ${ret}
}

# 将jpeg/png/bmp 转为 tiff
#param：$1 需要转码的文件一个，全路径的
#out： 成功返回 0， 输出 转码后的文件，全路径
function convert_image_to_tiff()
{
    local imagefile
    local value
    local ret
    local tmp_base_name     # 不带后缀，不带路径的文件名，用于生成tiff的文件名
    
    if [ $# -ne 1 ];then
        return 1
    fi
    imagefile=$1
    tmp_base_name=$(get_filebasename ${imagefile})
    
    value=`convert -density ${g_density} -units PixelsPerInch -resize ${g_size} ${imagefile} -background white -flatten ${g_tmp_pid_dir}/${tmp_base_name}.tiff 2>&1`
    ret=$?
    if [ ${ret} -ne 0 ];then
        log ERR "${value}"
        return ${ret}
    fi
    
    value=`convert ${g_white_tiff} -compose atop ${g_tmp_pid_dir}/${tmp_base_name}.tiff -composite ${g_tmp_pid_dir}/${tmp_base_name}.tiff 2>&1`
    ret=$?
    if [ ${ret} -ne 0 ];then
        log ERR "${value}"
        return ${ret}
    fi
    
    log DEBUG "convert_image_to_tiff ${imagefile} to ${g_tmp_pid_dir}/${tmp_base_name}.tiff success."
    echo "${g_tmp_pid_dir}/${tmp_base_name}.tiff"
    return 0
}

# 因为  tiff 存在多页的情况，需要单独处理，将tiff 的文件转为符合格式的tiff 文件
#param：$1 需要转码的文件一个，全路径的
#out： 成功返回 0， 输出 转码后的文件，全路径
function convert_tiff_to_tiff()
{
    local tifflist=""
    local pages=0
    local i=0
    local srcfile
    local tmp_base_name     # 不带后缀，不带路径的文件名，用于生成jpeg和tiff的文件名
    local ret=0
    local value=""
    
    if [ $# -ne 1 ];then
        return 1
    fi
    
    srcfile=$1
    tmp_base_name=$(get_filebasename ${srcfile})
    
    pages=$(tiffinfo $1 | grep TIFF | wc -l)
    ret=$?
    if [ ${ret} -ne 0 ];then
        log ERR "tiffinfo $1 failed !"
        return ${ret}
    fi
    
    #pdf 文件一页页的转为 jpeg，然后再转为tiff
    for((i=0;i<${pages};i++))
    do
        value=`convert -density ${g_density} -units PixelsPerInch -resize ${g_size} ${srcfile}[$i] -background white -flatten ${g_tmp_pid_dir}/${tmp_base_name}-${i}.tiff 2>&1`
        ret=$?
        if [ ${ret} -ne 0 ];then
            log ERR "${value}"
            break
        fi
        
        value=`convert ${g_white_tiff} -compose atop ${g_tmp_pid_dir}/${tmp_base_name}-${i}.tiff -composite ${g_tmp_pid_dir}/${tmp_base_name}-${i}.tiff 2>&1`
        ret=$?
        if [ ${ret} -ne 0 ];then
            log ERR "${value}"
            break
        fi        
        tifflist="${tifflist} ${tmp_base_name}-${i}.tiff"
    done
    
    local last_pwd=$(pwd)
    cd ${g_tmp_pid_dir}
    
    # 将 pdf 的tiff文件合并到一个 tiff
    value=`convert ${tifflist} ${tmp_base_name}.tiff 2>&1`
    ret=$?
    cd ${last_pwd}
    if [ ${ret} -ne 0 ];then
        log ERR "${value}"
    else
        echo "${g_tmp_pid_dir}/${tmp_base_name}.tiff"     # 输出全路径 的tiff文件
        log DEBUG "convert_pdf_to_tiff ${srcfile} to ${g_tmp_pid_dir}/${tmp_base_name}.tiff success."
    fi
    
    return ${ret} 
}
function convert_begin()
{
    local type=""
    local ret=1
    local value
    local srcfile=$1
    typeset -u local suffix=${srcfile##*.}    # 字符赋值为大写
    log DEBUG "${srcfile}-->suffix=${suffix}"
    case ${suffix} in 
        DOC|DOCX|TXT|XLS|XLSX|PPT|PPTX)

            value=$(convert_office_to_tiff ${srcfile})
            ret=$?
        ;;
        
        PDF)
            value=$(convert_pdf_to_tiff ${srcfile})
            ret=$?
        ;;
        
        BMP|DID|JPEG|JPG|JPE|JFIF|PNG)
            value=$(convert_image_to_tiff ${srcfile})
            ret=$?
        ;;
        TIF|TIFF)
            value=$(convert_tiff_to_tiff ${srcfile})
            ret=$?
            ;;
        "*")
            log ERR "${srcfile} file type nonsupport"
            ret=1
        ;;
    esac
    
    echo "${value}"
    return ${ret}

}

function main()
{
    local file=""
    local tifflist=""
    local ret=0
    local value=""
    local tmp_file=""
    local watermark_param=""
    declare -i local number=0
    if [ -z "${g_srcfilelist}" ];then
        log ERR "srcfile is empty !"
        return 1
    fi
    log DEBUG "g_srcfilelist=${g_srcfilelist}"
    for file in ${g_srcfilelist}
    do
        log DEBUG "begin file=${file}"
        
        #拷贝源文件，对文件重命名，防止文件名重复
        tmp_file=${file%.*}_${g_pid}_${number}.${file##*.}
        value=$(cp ${g_srcdir}/${file} ${g_tmp_pid_dir}/${tmp_file} 2>&1)
        ret=$?
        if [ ${ret} -ne 0 ];then
            log ERR "cp ${g_srcdir}/${file} ${g_tmp_pid_dir}/${tmp_file} failed ${value}"
            break
        fi
        
        value=$(convert_begin ${g_tmp_pid_dir}/${tmp_file})
        ret=$?
        if [ ${ret} -ne 0 ];then
            log ERR "convert_begin ${file} failed"
            break
        else
            tifflist="${tifflist} ${value}"
        fi
        number=number+1
    done
    
    if [ ${ret} -ne 0 ];then
        log ERR "convert ${g_srcfilelist} to ${g_tiffname} failed."
		echo ${value}
        return ${ret}
    fi
    log DEBUG "convert ${tifflist} ${g_tiffname}"
    #将 多个tiff 合并到目标tiff文件
    
    if [ ${g_watermark_flag} -eq 1 ];then
        value=`convert ${tifflist} -font ${g_font_file} -fill yellow -pointsize 100 -annotate ${g_watermark_position} "${g_watermark_string}" ${g_tiffname} 2>&1`
        
    else
        value=`convert ${tifflist} ${g_tiffname} 2>&1`
    fi
    ret=$?
    if [ ${ret} -ne 0 ];then
        log ERR "${value}"
    else
        log DEBUG "convert ${g_srcfilelist} to ${g_tiffname} success."
    fi
    echo ${value}
    return ${ret}
}

g_value=$(main)
g_ret=$?
rm -rf ${g_tmp_pid_dir}
echo ${g_value}
exit ${g_ret}
