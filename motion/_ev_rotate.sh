#!/bin/bash

# usage: ev_rotate.sh /tmp/motion/curr.jpg
ev_dir=/tmp/motion
snapshot1=c1_shot.jpg
snapshot2=c2_shot.jpg
eventpic1=c1_ev.jpg
eventpic2=c2_ev.jpg

[[ -z "$1" ]] && exit 0

if [[ "$1" == "$ev_dir/$snapshot1" ]]
then
  convert "$1" -thumbnail 640x360 -unsharp 0x.5 $ev_dir/c1_shot_preview.jpg
elif [[ "$1" == "$ev_dir/$snapshot2" ]]
then
  convert "$1" -thumbnail 640x360 -unsharp 0x.5 $ev_dir/c2_shot_preview.jpg
elif [[ "$1" == "$ev_dir/$eventpic1" ]]
then
  exit 0
elif [[ "$1" == "$ev_dir/$eventpic2" ]]
then
  for n in {10..2}
  do
    let np=n-1
    #echo "${n}.jpg ${np}.jpg"
    if [[ -w "$ev_dir/${np}.jpg" ]]
    then
      mv -f "$ev_dir/${np}.jpg" "$ev_dir/${n}.jpg"
      mv -f "$ev_dir/${np}_preview.jpg" "$ev_dir/${n}_preview.jpg"
    fi
  done
  cp -f "$1" $ev_dir/1.jpg
  convert "$1" -thumbnail 320x180 -unsharp 0x.5 $ev_dir/1_preview.jpg
fi

#echo "Written pic: $1" >> /tmp/t.log
