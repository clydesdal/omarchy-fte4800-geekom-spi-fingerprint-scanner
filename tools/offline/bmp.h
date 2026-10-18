/* SPDX-License-Identifier: LGPL-2.1-or-later
 * 8-bit BMP loader copied from tools/vendor-engine-test.c of
 * github.com/ibattus/geekom-fte4800-fingerprint-driver (Bharath Yadav). */
#pragma once
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
static uint16_t u16(const unsigned char*p){return p[0]|((uint16_t)p[1]<<8);}
static uint32_t u32(const unsigned char*p){return p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}

static int bmp(const char*path,uint8_t**out,int*w,int*h){
 FILE*f=fopen(path,"rb"); if(!f)return -1; unsigned char hd[54];
 if(fread(hd,1,54,f)!=54||hd[0]!='B'||hd[1]!='M'){fclose(f);return -2;}
 uint32_t off=u32(hd+10),dib=u32(hd+14); int32_t sw=(int32_t)u32(hd+18),sh=(int32_t)u32(hd+22);
 uint16_t bpp=u16(hd+28),cmp=u16(hd+30); if(sw<=0||sh==0||dib<40||cmp||bpp!=8){fclose(f);return -3;}
 int dh=sh<0?-sh:sh; size_t row=((size_t)sw+3)&~3u; uint8_t*img=malloc((size_t)sw*dh),*rb=malloc(row);
 if(!img||!rb){fclose(f);free(img);free(rb);return -4;} if(fseek(f,off,SEEK_SET)){fclose(f);free(img);free(rb);return -5;}
 for(int y=0;y<dh;y++){if(fread(rb,1,row,f)!=row){free(img);free(rb);fclose(f);return -6;}
  int dy=sh>0?dh-1-y:y; for(int x=0;x<sw;x++)img[dy*sw+x]=rb[x];
 } fclose(f);free(rb);*out=img;*w=sw;*h=dh;return 0;
}
