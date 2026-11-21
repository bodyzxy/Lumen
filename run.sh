#!/bin/bash
# 编译并运行 Lumen（release 模式，调色预览才流畅）
# 第一次编译需要 1～3 分钟，之后只编译改动的文件
cd "$(dirname "$0")"
swift run -c release Lumen
