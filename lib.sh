#!/bin/bash
# Telegram MTProto Proxy 共用函数库

to_bytes() {
    local value unit
    value=$(printf "%s" "$1" | sed -E 's/^([0-9.]+).*/\1/')
    unit=$(printf "%s" "$1" | sed -E 's/^[0-9.]+([A-Za-z]+)$/\1/')

    awk -v value="$value" -v unit="$unit" '
        BEGIN {
            if (value == "" || unit == "") {
                print 0
                exit
            }
            scale["B"] = 1
            scale["kB"] = 1000
            scale["MB"] = 1000^2
            scale["GB"] = 1000^3
            scale["TB"] = 1000^4
            scale["KiB"] = 1024
            scale["MiB"] = 1024^2
            scale["GiB"] = 1024^3
            scale["TiB"] = 1024^4
            printf "%.0f\n", value * scale[unit]
        }
    '
}

format_gib() {
    awk -v bytes="$1" 'BEGIN { printf "%.2fGiB", bytes / 1024 / 1024 / 1024 }'
}
