#!/usr/bin/env ash
set -euo pipefail
#
# 用法：
#   ./analyze_size.sh [--force] <label> [<compare_label>]
#
# 示例：
#   ./analyze_size.sh 1         # 如果快照 1 不存在，则生成快照 1；否则保持原有快照
#   ./analyze_size.sh --force 1 # 强制更新生成快照 1
#
#   ./analyze_size.sh 2         # 同上，生成快照 2
#   ./analyze_size.sh 2 1       # 使用当前快照 2（不更新，如果已存在）对比快照 1，输出：快照2 -> (快照2-快照1)
#   ./analyze_size.sh 1 2       # 使用当前快照 1对比快照 2，输出：快照1 -> (快照1-快照2)
#

# 如果第一个参数为 --force，则打开更新标志并 shift 参数
FORCE_UPDATE=0
if [[ "${1:-}" == "--force" ]]; then
    FORCE_UPDATE=1
    shift
fi

LABEL="${1:-snapshot}"
COMPARE_TO="${2:-}"
REPORT_BASE="/var/log/image_size"
REPORT_FILE="${REPORT_BASE}_report.log"
# 快照数据保存到此文件，格式：目录<TAB>字节数
DATA_FILE="${REPORT_BASE}_${LABEL}_data.txt"

mkdir -p /var/log

# 定义需要采集快照的目录（示例中使用常用的几个目录，可按需求修改）
DIRS="/usr/local /root /opt /var/lib /var/cache"

# -------------------------------
# 生成快照 —— 如果指定的快照文件已存在且未使用 --force 参数，则不更新，
# 保证已生成的快照文件内容保持不变，便于将来对比。
# -------------------------------
if [[ ! -f "${DATA_FILE}" || "${FORCE_UPDATE}" -eq 1 ]]; then
    > "${DATA_FILE}"
    for base in "${DIRS}"; do
        if [[ -d "${base}" ]]; then
            # 使用 du -sb 获取字节数
            find "${base}" -mindepth 1 -maxdepth 1 -exec du -sb {} + 2>/dev/null | \
            awk '{print $2 "\t" $1}' >> "${DATA_FILE}"
        else
            # 如果目录不存在，写入0
            echo -e "${base}\t0" >> "${DATA_FILE}"
        fi
    done
    echo "[信息] 快照 ${LABEL} 已生成或更新：${DATA_FILE}"
else
    echo "[信息] 快照 ${LABEL} 已存在，跳过采集。如需更新请使用 --force 参数。"
fi

# 定义一个 shell 函数，把字节转换为人类可读格式（单位：b, KB, MB, GB）
hr() {
    bytes=$1
    if [ "$bytes" -lt 1024 ]; then
        echo "${bytes}b"
    elif [ "$bytes" -lt $((1024*1024)) ]; then
        kb=$(awk -v b="$bytes" 'BEGIN {printf "%.0f", b/1024}')
        echo "${kb}KB"
    elif [ "$bytes" -lt $((1024*1024*1024)) ]; then
        mb=$(awk -v b="$bytes" 'BEGIN {printf "%.0f", b/(1024*1024)}')
        echo "${mb}MB"
    else
        gb=$(awk -v b="$bytes" 'BEGIN {printf "%.0f", b/(1024*1024*1024)}')
        echo "${gb}GB"
    fi
}

# -------------------------------
# 打印当前快照（按目录排序，每行显示：目录<TAB>大小）
# -------------------------------
echo "=== [${LABEL}] 镜像体积快照 $(date '+%F %T') ==="
echo ""
sort -k1,1 "${DATA_FILE}" | while IFS=$'\t' read -r dir size; do
    echo -e "${dir}\t$(hr "$size")"
done
echo ""

{
    echo "=== [${LABEL}] 镜像体积快照 $(date '+%F %T') ==="
    sort -k1,1 "${DATA_FILE}" | while IFS=$'\t' read -r d s; do
        echo -e "${d}\t$(hr "$s")"
    done
    echo ""
} >> "${REPORT_FILE}"

# -------------------------------
# 若指定了对比快照（第二个参数），则进行对比输出。
#
# 对比时：当前快照文件 ($DATA_FILE) 与之前的快照文件 (COMPARE_DATA_FILE)
# 差值计算采用： diff = (当前快照 - 对比快照)
# 注意：对比快照（第二个参数传入的那个标签）必须已存在，否则报错。
# -------------------------------
if [[ -n "${COMPARE_TO}" ]]; then
    COMPARE_DATA_FILE="${REPORT_BASE}_${COMPARE_TO}_data.txt"
    if [[ ! -f "${COMPARE_DATA_FILE}" ]]; then
        echo "对比数据文件 ${COMPARE_DATA_FILE} 不存在！" >&2
        exit 1
    fi

    echo "🔍 [对比] ${COMPARE_TO} ➜ ${LABEL} 体积变化:"
    echo ""

    TMP_OLD=$(mktemp)
    TMP_NEW=$(mktemp)
    sort -k1,1 "${COMPARE_DATA_FILE}" > "${TMP_OLD}"
    sort -k1,1 "${DATA_FILE}" > "${TMP_NEW}"

    join -a1 -a2 -e "0" -o '0,1.2,2.2' -t $'\t' "${TMP_OLD}" "${TMP_NEW}" | \
    awk -F '\t' '
    function human(x) {
       if(x < 1024) return x "b";
       else if(x < 1024*1024) return sprintf("%.0fKB", x/1024);
       else if(x < 1024*1024*1024) return sprintf("%.0fMB", x/(1024*1024));
       else return sprintf("%.0fGB", x/(1024*1024*1024));
    }
    {
       # $1:目录，$2:对比快照（旧）的字节数，$3:当前快照的字节数
       dir = $1;
       old = $2;
       new = $3;
       diff = new - old;
       absdiff = (diff < 0 ? -diff : diff);
       if(diff > 0)
           diff_str = "->(+" human(absdiff) ")";
       else if(diff < 0)
           diff_str = "->(-" human(absdiff) ")";
       else
           diff_str = "->(" human(0) ")";
       printf "%-20s\t%s %s\n", dir, human(new), diff_str;
    }'
    rm -f "${TMP_OLD}" "${TMP_NEW}"
fi