#!/bin/bash

host="localhost"
port="2121"

for i in {0..5000}
do
ftp -n -u -i "${host}" "${port}" <<END_COMMANDS
passive
cd /Pictures/Cameras/Kitchen
put test-file "test-file-${i}"
quit
END_COMMANDS
done
