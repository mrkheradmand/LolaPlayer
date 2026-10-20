// Decode an entire fixture through the app's actual bundled libmpv (no UI/audio output).
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
typedef struct {int event_id;int error;unsigned long long reply_userdata;void *data;} Event;
typedef struct {int reason;int error;} End;
int main(int argc,char **argv){
 if(argc!=3)return 2;
 void *lib=dlopen(argv[1],RTLD_NOW|RTLD_LOCAL);if(!lib){fprintf(stderr,"%s\n",dlerror());return 3;}
 void *(*create)(void)=dlsym(lib,"mpv_create");
 int (*option)(void*,const char*,const char*)=dlsym(lib,"mpv_set_option_string");
 int (*initialize)(void*)=dlsym(lib,"mpv_initialize");
 int (*command)(void*,const char**)=dlsym(lib,"mpv_command");
 Event *(*wait)(void*,double)=dlsym(lib,"mpv_wait_event");
 void (*destroy)(void*)=dlsym(lib,"mpv_terminate_destroy");
 if(!create||!option||!initialize||!command||!wait||!destroy)return 4;
 void *mpv=create();if(!mpv)return 5;
 option(mpv,"config","no");option(mpv,"terminal","no");option(mpv,"vo","null");option(mpv,"ao","null");
 option(mpv,"untimed","yes");option(mpv,"idle","yes");option(mpv,"audio-display","no");
 if(initialize(mpv)<0)return 6;
 const char *args[]={"loadfile",argv[2],"replace",NULL};
 if(command(mpv,args)<0)return 7;
 int loaded=0,status=8;time_t start=time(NULL);
 while(time(NULL)-start<20){
  Event *event=wait(mpv,0.1);
  if(event->event_id==8)loaded=1;
  if(event->event_id==7){End *end=event->data;status=loaded&&end&&end->reason==0&&end->error>=0?0:9;break;}
 }
 destroy(mpv);if(status)fprintf(stderr,"Decode failed (%d): %s\n",status,argv[2]);return status;
}
