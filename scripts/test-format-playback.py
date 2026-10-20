#!/usr/bin/env python3
"""Create short synthetic fixtures, then decode with the packaged libmpv.

Fixture generation uses a developer FFmpeg CLI; no encoders or conversion UI
are added to Lola. Formats without fixture encoders are not marked tested.
"""
from pathlib import Path
import json
import os
import shutil
import subprocess

root = Path(__file__).resolve().parent.parent
fixtures = root/'.build/format-fixtures'
fixtures.mkdir(parents=True, exist_ok=True)
frameworks = root/'dist/Lola Player.app/Contents/Frameworks'
checker = fixtures/'check-decoding'
subprocess.run(['clang', str(root/'scripts/check-decoding.c'), '-Wl,-rpath,'+str(frameworks), '-o', str(checker)], check=True)
ffmpeg = os.environ.get('FFMPEG', shutil.which('ffmpeg') or '/opt/homebrew/bin/ffmpeg')
# extension, codec, muxer; a separate fixture tests each container/codec combination.
audio = [('aiff','pcm_s16be','aiff'),('caf','pcm_s16le','caf'),('au','pcm_s16be','au'),
         ('wv','wavpack','wv'),('tta','tta','tta'),('mka','flac','matroska'),('oga','flac','ogg'),
         ('weba','libopus','webm'),('wma','wmav2','asf'),('ac3','ac3','ac3'),('eac3','eac3','eac3'),
         ('dts','dca','dts'),('thd','truehd','truehd'),('mlp','mlp','mlp')]
video = [('3gp','mpeg4','3gp'),('f4v','libx264','f4v'),('asf','wmv2','asf'),
         ('m2ts','mpeg2video','mpegts'),('mts','mpeg2video','mpegts'),('vob','mpeg2video','vob'),
         ('ivf','libvpx','ivf'),('y4m','rawvideo','yuv4mpegpipe'),('rm','rv10','rm')]
results=[]
for extension,codec,muxer in audio+video:
    path=fixtures/('sample.'+extension)
    is_audio=(extension,codec,muxer) in audio
    source='sine=frequency=440:sample_rate=48000:duration=1' if is_audio else 'testsrc2=size=176x144:rate=25:duration=1'
    command=[ffmpeg,'-hide_banner','-loglevel','error','-y','-f','lavfi','-i',source,'-threads','1']
    command+=['-c:a' if is_audio else '-c:v',codec,'-strict','-2','-f',muxer,str(path)]
    generated=subprocess.run(command,capture_output=True,text=True)
    if generated.returncode:
        results.append({'extension':extension,'status':'fixture-unavailable','detail':generated.stderr.strip()})
        continue
    result=subprocess.run([str(checker),str(frameworks/'libmpv.2.dylib'),str(path)],capture_output=True,text=True,timeout=30)
    results.append({'extension':extension,'status':'passed' if result.returncode==0 else 'failed','detail':result.stderr.strip()})
# HLS needs to remain one demuxed input, rather than opening each .ts segment.
hls=fixtures/'hls'
hls.mkdir(exist_ok=True)
manifest=hls/'index.m3u8'
subprocess.run([ffmpeg,'-hide_banner','-loglevel','error','-y','-f','lavfi','-i','testsrc2=size=176x144:rate=10:duration=3','-c:v','libx264','-threads','1','-g','10','-hls_time','1','-hls_list_size','0',str(manifest)],check=True)
result=subprocess.run([str(checker),str(frameworks/'libmpv.2.dylib'),str(manifest)],capture_output=True,text=True,timeout=30)
results.append({'extension':'local-hls','status':'passed' if result.returncode==0 else 'failed','detail':result.stderr.strip()})
report=fixtures/'results.json'
report.write_text(json.dumps(results,indent=2)+'\n')
for item in results: print(item['extension']+': '+item['status'],flush=True)
print('Report:',report)
raise SystemExit(1 if any(item['status']=='failed' for item in results) else 0)
