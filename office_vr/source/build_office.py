#!/usr/bin/env python3
"""Photo-guided office reconstruction. Python 3 + numpy + Pillow; no Blender needed.

Writes a portable glTF 2.0 binary, a separate collision proxy GLB, and collider JSON.
Coordinate convention: metres, Y up, +Z entry, -X taupe wall. Width is measured;
all other dimensions are estimates. Textures are original procedural materials.
"""
import argparse, io, json, math, struct
from pathlib import Path
from collections import defaultdict
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

W, D, H = 3.7846, 3.6576, 2.7432
OUT = Path(__file__).resolve().parents[1]
RNG = np.random.default_rng(73)

def linear(c):
    return [((v/255+.055)/1.055)**2.4 if v/255>.04045 else v/255/12.92 for v in c]

def rotation(y):
    c,s=math.cos(y),math.sin(y)
    return np.array([[c,0,s],[0,1,0],[-s,0,c]],float)

class Scene:
    def __init__(self):
        self.g={"asset":{"version":"2.0","generator":"Office photo reconstruction / build_office.py","extras":{"units":"metres","measured_width_m":W,"estimated_depth_m":D,"estimated_height_m":H}},"scene":0,"scenes":[{"name":"Office","nodes":[0]}],"nodes":[{"name":"Office_Root","children":[],"extras":{"units":"metres","reference_photos":8,"width_measured":True}}],"meshes":[],"materials":[],"textures":[],"images":[],"samplers":[{"magFilter":9729,"minFilter":9987,"wrapS":10497,"wrapT":10497}],"accessors":[],"bufferViews":[]}
        self.blob=bytearray();self.mats={};self.textures={};self.groups=[];self.colliders=[]

    def blobview(self,b,target=None):
        while len(self.blob)%4:self.blob.append(0)
        v={"buffer":0,"byteOffset":len(self.blob),"byteLength":len(b)}
        if target:v['target']=target
        self.blob.extend(b); self.g['bufferViews'].append(v)
        return len(self.g['bufferViews'])-1

    def texture(self,name,im):
        f=io.BytesIO();im.save(f,format='PNG',optimize=True)
        v=self.blobview(f.getvalue());n=len(self.g['images'])
        self.g['images'].append({'name':name,'bufferView':v,'mimeType':'image/png'})
        self.g['textures'].append({'sampler':0,'source':n});self.textures[name]=n

    def material(self,name,rgb=(255,255,255),rough=.8,metal=0,tex=None,alpha=1,emission=None):
        m={'name':name,'pbrMetallicRoughness':{'baseColorFactor':linear(rgb)+[alpha],'metallicFactor':metal,'roughnessFactor':rough}}
        if tex:m['pbrMetallicRoughness']['baseColorTexture']={'index':self.textures[tex]}
        if alpha<1:m.update(alphaMode='BLEND',doubleSided=True)
        if emission:m['emissiveFactor']=emission
        self.mats[name]=len(self.g['materials']);self.g['materials'].append(m)

    def group(self,name,pos=(0,0,0),yaw=0,extras=None):
        q=Group(self,name,pos,yaw,extras);self.groups.append(q);return q

    def accessor(self,a,typ,component=5126,target=34962):
        dtype='<f4' if component==5126 else '<u4'
        a=np.asarray(a,dtype=dtype)
        idx=self.blobview(a.tobytes(),target)
        acc={'bufferView':idx,'componentType':component,'count':len(a),'type':typ}
        if typ=='VEC3':acc.update(min=a.min(axis=0).tolist(),max=a.max(axis=0).tolist())
        self.g['accessors'].append(acc);return len(self.g['accessors'])-1

    def save(self,path):
        stats={'triangles':0,'vertices':0,'mesh_primitives':0,'meshes':len(self.groups),'materials':len(self.mats),'embedded_textures':len(self.textures)}
        for grp in self.groups:
            primitives=[]
            for mat,data in grp.data.items():
                p,n,uv,inds=data
                if not inds:continue
                attrs={'POSITION':self.accessor(p,'VEC3'),'NORMAL':self.accessor(n,'VEC3')}
                if 'baseColorTexture' in self.g['materials'][self.mats[mat]]['pbrMetallicRoughness']:
                    attrs['TEXCOORD_0']=self.accessor(uv,'VEC2')
                primitives.append({'attributes':attrs,'indices':self.accessor(inds,'SCALAR',5125,34963),'material':self.mats[mat]})
                stats['triangles']+=len(inds)//3;stats['vertices']+=len(p);stats['mesh_primitives']+=1
            meshid=len(self.g['meshes']);self.g['meshes'].append({'name':grp.name,'primitives':primitives})
            node={'name':grp.name,'mesh':meshid,'translation':list(grp.pos),'rotation':[0,math.sin(grp.yaw/2),0,math.cos(grp.yaw/2)]}
            if grp.extras:node['extras']=grp.extras
            nid=len(self.g['nodes']);self.g['nodes'].append(node);self.g['nodes'][0]['children'].append(nid)
        for i,node in enumerate(self.g['nodes']):
            if node['name']=='Door_Hinge':
                times=self.accessor([0,1],'SCALAR',target=None)
                self.g['accessors'][times].update(min=[0],max=[1])
                q=[0,math.sin(math.radians(-95)/2),0,math.cos(math.radians(-95)/2)]
                self.g['animations']=[]
                for name,values in [('Door_Open',[[0,0,0,1],q]),('Door_Close',[q,[0,0,0,1]])]:
                    output=self.accessor(values,'VEC4',target=None)
                    self.g['animations'].append({'name':name,'samplers':[{'input':times,'output':output,'interpolation':'LINEAR'}],'channels':[{'sampler':0,'target':{'node':i,'path':'rotation'}}]})
        if not self.g['images']:
            for key in ['images','textures','samplers']:self.g.pop(key)
        self.g['buffers']=[{'byteLength':len(self.blob)}]
        self.g['asset']['extras']['statistics']=stats
        j=json.dumps(self.g,separators=(',',':')).encode()
        j+=b' '*((-len(j))%4);self.blob.extend(b'\0'*((-len(self.blob))%4))
        path.write_bytes(struct.pack('<III',0x46546c67,2,28+len(j)+len(self.blob))+struct.pack('<II',len(j),0x4e4f534a)+j+struct.pack('<II',len(self.blob),0x004e4942)+self.blob)
        stats['glb_bytes']=path.stat().st_size
        return stats

class Group:
    def __init__(self,scene,name,pos,yaw,extras):
        self.scene=scene;self.name=name;self.pos=pos;self.yaw=yaw;self.extras=extras or {};self.data=defaultdict(lambda:[[],[],[],[]])

    def mesh(self,mat,p,faces,uv=None,normals=None):
        p=np.asarray(p,float);faces=np.asarray(faces,int)
        if normals is None:
            normals=np.zeros_like(p)
            for f in faces:
                a,b,c=p[f];n=np.cross(b-a,c-a);ln=np.linalg.norm(n)
                if ln>1e-12:n/=ln
                normals[f]+=n
            ln=np.linalg.norm(normals,axis=1,keepdims=True);normals/=np.maximum(ln,1e-12)
        if uv is None:uv=np.zeros((len(p),2))
        dest=self.data[mat];off=len(dest[0]);dest[0].extend(p.tolist());dest[1].extend(np.asarray(normals).tolist());dest[2].extend(np.asarray(uv).tolist());dest[3].extend((faces+off).reshape(-1).tolist())

    def quad(self,mat,p,uv=None):
        self.mesh(mat,p,[[0,1,2],[0,2,3]],uv or [(0,0),(1,0),(1,1),(0,1)])

    def box(self,mat,c,size,yaw=0,uvscale=(1,1)):
        x,y,z=np.array(size)/2
        # Each quad is CCW from outside, with a dedicated normal and UV island.
        quads=[[(x,-y,-z),(x,y,-z),(x,y,z),(x,-y,z)],
               [(-x,-y,z),(-x,y,z),(-x,y,-z),(-x,-y,-z)],
               [(-x,y,-z),(-x,y,z),(x,y,z),(x,y,-z)],
               [(-x,-y,z),(-x,-y,-z),(x,-y,-z),(x,-y,z)],
               [(x,-y,z),(x,y,z),(-x,y,z),(-x,-y,z)],
               [(-x,-y,-z),(-x,y,-z),(x,y,-z),(x,-y,-z)]]
        r=rotation(yaw);u,v=uvscale
        for q in quads:self.quad(mat,np.asarray(q)@r.T+c,[(0,v),(0,0),(u,0),(u,v)])

    def cyl(self,mat,a,b,r,r2=None,seg=16):
        a,b=np.array(a,float),np.array(b,float);axis=b-a;axis/=np.linalg.norm(axis)
        seed=np.array([0,0,1]) if abs(axis[2])<.9 else np.array([1,0,0])
        u=np.cross(axis,seed);u/=np.linalg.norm(u);v=np.cross(axis,u);r2=r if r2 is None else r2
        p=[];uv=[];ns=[]
        slope=(r-r2)/np.linalg.norm(b-a)
        for origin,rad,yy in [(a,r,0),(b,r2,1)]:
            for i in range(seg+1):
                t=2*math.pi*i/seg;d=u*math.cos(t)+v*math.sin(t)
                p.append(origin+rad*d);nn=d+axis*slope;ns.append(nn/np.linalg.norm(nn));uv.append((i/seg,yy))
        f=[]
        for i in range(seg):f.extend([[i,i+1,i+seg+2],[i,i+seg+2,i+seg+1]])
        self.mesh(mat,p,f,uv,ns)
        for origin,rad,sign in [(a,r,-1),(b,r2,1)]:
            p=[origin];uv=[(.5,.5)]
            for i in range(seg):
                t=2*math.pi*i/seg;p.append(origin+rad*(u*math.cos(t)+v*math.sin(t)));uv.append((.5+.5*math.cos(t),.5+.5*math.sin(t)))
            fs=[[0,i+1,(i+1)%seg+1] for i in range(seg)]
            if sign<0:fs=[f[::-1] for f in fs]
            self.mesh(mat,p,fs,uv,[axis*sign]*(seg+1))

    def tube(self,mat,points,r=.01,seg=10):
        for a,b in zip(points,points[1:]):self.cyl(mat,a,b,r,seg=seg)

    def rounded(self,mat,c,size,r=.03,seg=5,yaw=0):
        # Rounded rectangle extruded along Y, with separate face/edge normals.
        w,h,d=size;outline=[]
        for cx,cz,start in [(w/2-r,d/2-r,0),(-w/2+r,d/2-r,90),(-w/2+r,-d/2+r,180),(w/2-r,-d/2+r,270)]:
            for i in range(seg+1):
                t=math.radians(start+i*90/seg);outline.append([cx+r*math.cos(t),cz+r*math.sin(t)])
        R=rotation(yaw);N=len(outline)
        def trans(p):return np.asarray(p)@R.T+c
        for yy,sgn in [(-h/2,-1),(h/2,1)]:
            p=[[0,yy,0]]+[[x,yy,z] for x,z in outline]
            f=[[0,(i+1)%N+1,i+1] for i in range(N)]
            if sgn<0:f=[a[::-1] for a in f]
            uv=[(.5,.5)]+[(x/w+.5,z/d+.5) for x,z in outline]
            self.mesh(mat,trans(p),f,uv,[[0,sgn,0]]*(N+1))
        for i in range(N):
            x,z=outline[i];xx,zz=outline[(i+1)%N]
            self.quad(mat,trans([[x,-h/2,z],[x,h/2,z],[xx,h/2,zz],[xx,-h/2,zz]]))

    def collider(self,name,c,size,yaw=0,kind='box'):
        self.scene.colliders.append({'name':name,'parent':self.name,'type':kind,'center':list(c),'size':list(size),'yaw_radians':yaw,'parent_position':list(self.pos),'parent_yaw_radians':self.yaw})

def textures(s):
    # 2 x 2 carpet tiles, quarter-turned as in the photographs. 1.2192m repeat.
    N=1024;tile=512;a=np.zeros((N,N,3),np.float32)
    for j in range(2):
        for i in range(2):
            lines=RNG.normal(0,13,tile)
            lines=np.convolve(lines,[.2,.6,.2],mode='same')
            lines+=7*np.sin(np.arange(tile)*.39)+4*np.sin(np.arange(tile)*.09)
            base=np.tile(lines,(tile,1))+RNG.normal(0,3,(tile,tile))
            base+=np.sin(np.arange(tile)[:,None]*2.1)*2
            patch=np.array([131,126,113])[None,None,:]+base[:,:,None]
            if (i+j)%2:patch=np.rot90(patch)
            patch[:2]*=.85;patch[:,:2]*=.85
            a[j*tile:(j+1)*tile,i*tile:(i+1)*tile]=patch
    s.texture('Carpet_QuarterTurn',Image.fromarray(np.uint8(np.clip(a,0,255))))
    # Continuous vertical birch grain; generated without photographed lighting.
    h,w=1024,512;yy,xx=np.mgrid[0:h,0:w]
    warp=xx+4*np.sin(yy*.009)+2*np.sin(yy*.023+xx*.018)
    grain=1.6*np.sin(warp*.48)+1.3*np.sin(warp*1.61)+.8*np.sin(warp*2.43)
    fibers=np.array(Image.fromarray(np.uint8(RNG.uniform(100,155,(64,256)))).resize((w,h),Image.Resampling.BICUBIC),float)-127.5
    grain+=fibers*.22+RNG.normal(0,1.2,(h,w))
    birch=np.array([192,159,105])[None,None,:]+grain[:,:,None]
    s.texture('Birch',Image.fromarray(np.uint8(np.clip(birch,0,255))))
    a=RNG.normal(220,2,(512,512));dots=RNG.random(a.shape)<.055;a[dots]-=RNG.uniform(35,100,dots.sum())
    a=Image.fromarray(np.uint8(np.clip(a,0,255))).convert('RGB')
    s.texture('AcousticTile',a)
    a=np.ones((128,128,3))*np.array([119,124,126]);a[::3,:,:]*=.73;a[:,::3,:]*=.72
    s.texture('ChairWoven',Image.fromarray(np.uint8(a)))

def materials(s):
    s.material('WarmWhite',(226,225,216),.88)
    s.material('TaupeWall',(167,158,139),.92)
    s.material('Baseboard',(181,174,154),.75)
    s.material('Carpet',tex='Carpet_QuarterTurn',rough=1)
    s.material('Ceiling',tex='AcousticTile',rough=1)
    s.material('BirchDoor',tex='Birch',rough=.57)
    s.material('MapleTable',(255,237,184),tex='Birch',rough=.48)
    s.material('WhiteLaminate',(232,236,233),.48)
    s.material('GreySteel',(158,165,166),.4,.55)
    s.material('Chrome',(194,201,201),.25,.85)
    s.material('BlackPolymer',(29,32,32),.62)
    s.material('Rubber',(18,20,21),.94)
    s.material('ChairMesh',tex='ChairWoven',rough=.93)
    s.material('BlueFabric',(25,43,62),.96)
    s.material('ShelfPutty',(146,145,126),.72,.12)
    s.material('ShelfInside',(117,116,100),.85)
    s.material('YellowTape',(235,207,27),.9)
    s.material('BagLiner',(169,176,175),.46)
    s.material('Cardboard',(150,106,53),1)
    s.g['materials'][-1]['doubleSided']=True
    s.material('Glass',(175,210,219),.15,0,alpha=.19)
    s.material('Diffuser',(244,246,238),.4,emission=[1,1,.92])
    s.material('Orange',(224,130,30),.6)

def architecture(s):
    f=s.group('Floor');f.box('Carpet',(0,-.055,0),(W,.11,D),uvscale=(W/1.2192,D/1.2192));f.collider('Floor',(0,-.055,0),(W,.11,D))
    # Maximum width is the user's 12 ft 5 in. Rear desk recess is inferred.
    wall=s.group('Wall_Accent');wall.box('TaupeWall',(-W/2-.065,H/2,0),(.13,H,D));wall.box('Baseboard',(-W/2+.008,.055,0),(.018,.11,D));wall.collider('AccentWall',(-W/2-.065,H/2,0),(.13,H,D))
    wall=s.group('Wall_Right');wall.box('WarmWhite',(W/2+.065,H/2,0),(.13,H,D));wall.box('Baseboard',(W/2-.008,.055,0),(.018,.11,D));wall.collider('RightWall',(W/2+.065,H/2,0),(.13,H,D))
    wall=s.group('Wall_Rear');wall.box('WarmWhite',(0,H/2,-D/2-.065),(W,H,.13));wall.box('WarmWhite',(.94,H/2,-D/2+.105),(W/2+.012,H,.21));wall.box('Baseboard',(-.95,.055,-D/2+.008),(W/2-.01,.11,.018));wall.box('Baseboard',(.94,.055,-D/2+.222),(W/2+.01,.11,.018));wall.box('Baseboard',(-.015,.055,-D/2+.107),(.018,.11,.22));wall.collider('RearWall',(0,H/2,-D/2-.065),(W,H,.13));wall.collider('RearWallJog',(.94,H/2,-D/2+.105),(W/2+.012,H,.21))
    e=s.group('Wall_Entry');lo,hi=.12,1.66;dh=2.16
    for l,r in [(-W/2,lo),(hi,W/2)]:
        e.box('WarmWhite',((l+r)/2,H/2,D/2+.065),(r-l,H,.13));e.box('Baseboard',((l+r)/2,.055,D/2-.008),(r-l,.11,.018));e.collider('EntryPier',((l+r)/2,H/2,D/2+.065),(r-l,H,.13))
    e.box('WarmWhite',((lo+hi)/2,(H+dh)/2,D/2+.065),(hi-lo,H-dh,.13));e.collider('EntryHeader',((lo+hi)/2,(H+dh)/2,D/2+.065),(hi-lo,H-dh,.13))
    for x in [lo+.03,.62,hi-.03]:e.box('Baseboard',(x,dh/2,D/2),(.06,dh,.13))
    e.box('Baseboard',((lo+hi)/2,dh-.025,D/2),(hi-lo,.055,.13))
    # Narrow sidelight, clear glazing. Beyond the room is intentionally unspecified.
    e.box('Baseboard',(.375,.04,D/2),(.45,.08,.13))
    e.box('Glass',(.375,1.09,D/2+.015),(.42,2.02,.008));e.collider('Sidelight',(.375,1.09,D/2+.015),(.44,2.1,.05))
    for x in [.177,.576]:e.box('WhiteLaminate',(x,1.09,D/2-.026),(.014,2.025,.02))
    for y in [.085,2.10]:e.box('WhiteLaminate',(.375,y,D/2-.026),(.415,.014,.02))
    e.box('BlackPolymer',(.375,1.48,D/2-.004),(.135,.14,.014))
    # Door pivot is on the right jamb in world coordinates, opening inward at -Y rotation.
    door=s.group('Door_Hinge',(1.598,0,D/2),extras={'interactive':'hinged_door','hinge_axis':'Y','closed_degrees':0,'open_degrees':-95})
    door.box('BirchDoor',(-.471,1.058,0),(.934,2.106,.043));door.collider('Door',(-.471,1.058,0),(.934,2.106,.043))
    for yy in [.27,1.06,1.87]:
        door.cyl('Chrome',(-.004,yy-.046,-.016),(-.004,yy+.046,-.016),.009,seg=12)
    for z,sgn in [(-.028,-1),(.028,1)]:
        door.cyl('Chrome',(-.81,.98,z),(-.81,.98,z+sgn*.014),.032,seg=24)
        door.cyl('Chrome',(-.81,.98,z),(-.81,.98,z+sgn*.065),.011,seg=12)
        door.cyl('Chrome',(-.81,.98,z+sgn*.06),(-.72,.98,z+sgn*.06),.011,seg=12)
    door.cyl('Chrome',(-.47,1.32,-.025),(-.47,1.32,-.048),.009,seg=10)
    door.tube('Chrome',[(-.47,1.32,-.048),(-.47,1.29,-.066),(-.45,1.28,-.07),(-.43,1.30,-.065)],.004,8)

def ceiling(s):
    ceil=s.group('Ceiling_Grid',extras={'preview_hide':True})
    xs=sorted(set([-W/2,W/2]+[i*.6096 for i in range(-3,4)]));zs=[i*.6096 for i in range(-3,4)]
    specials={(2,1):'light',(5,4):'light',(5,1):'vent',(4,4):'supply'}
    for i,(x0,x1) in enumerate(zip(xs,xs[1:])):
        for j,(z0,z1) in enumerate(zip(zs,zs[1:])):
            x,z=(x0+x1)/2,(z0+z1)/2;w,d=x1-x0,z1-z0
            kind=specials.get((i,j))
            if kind is None:ceil.box('Ceiling',(x,H+.018,z),(w-.012,.035,d-.012))
            else:
                if kind=='light':
                    # Recessed square well above the ceiling plane, with one tube
                    # across its centre. Only the thin square trim is at H.
                    ceil.box('WhiteLaminate',(x,H+.105,z),(w-.02,.012,d-.02))
                    for xx in [x-w/2+.023,x+w/2-.023]:
                        ceil.box('WarmWhite',(xx,H+.052,z),(.015,.10,d-.032))
                        ceil.box('WhiteLaminate',(xx,H-.002,z),(.030,.008,d-.012))
                    for zz in [z-d/2+.023,z+d/2-.023]:
                        ceil.box('WarmWhite',(x,H+.052,zz),(w-.032,.10,.015))
                        ceil.box('WhiteLaminate',(x,H-.002,zz),(w-.012,.008,.030))
                    ceil.cyl('Diffuser',(x-w/2+.065,H+.043,z),(x+w/2-.065,H+.043,z),.016,seg=20)
                    for xx in [x-w/2+.061,x+w/2-.061]:
                        ceil.box('WhiteLaminate',(xx,H+.052,z),(.026,.055,.045))
                elif kind=='vent':
                    ceil.box('WhiteLaminate',(x,H+.055,z),(w-.014,.035,d-.014))
                    ceil.box('BlackPolymer',(x,H+.025,z),(.40,.02,.40))
                    for size,drop in [(.42,0),(.32,.022),(.22,.043),(.12,.062)]:
                        for xx in [x-size/2,x+size/2]:ceil.box('WhiteLaminate',(xx,H-drop,z),(.025,.018,size))
                        for zz in [z-size/2,z+size/2]:ceil.box('WhiteLaminate',(x,H-drop,zz),(size,.018,.025))
                    ceil.box('WhiteLaminate',(x,H-.07,z),(.09,.02,.09))
                else:
                    ceil.box('WhiteLaminate',(x,H+.055,z),(w-.014,.035,d-.014))
                    ceil.box('BlackPolymer',(x,H+.025,z),(.44,.012,.44));ceil.box('WhiteLaminate',(x,H-.045,z),(.43,.025,.43))
    for x in xs:ceil.box('WarmWhite',(x,H-.004,0),(.014,.016,D))
    for z in zs:ceil.box('WarmWhite',(0,H-.004,z),(W,.016,.014))
    for x in [-W/2+.012,W/2-.012]:ceil.box('Baseboard',(x,H-.015,0),(.024,.026,D))
    for z in [-D/2+.012,D/2-.012]:ceil.box('Baseboard',(0,H-.015,z),(W,.026,.024))
    ceil.cyl('Chrome',(.12,H-.012,.49),(.12,H-.027,.49),.031,seg=20)
    ceil.cyl('Chrome',(.12,H-.027,.49),(.12,H-.065,.49),.009,seg=10)
    ceil.cyl('WarmWhite',(.12,H-.066,.49),(.12,H-.072,.49),.019,seg=12)
    ceil.collider('Ceiling',(0,H+.045,0),(W,.09,D))

def guest_chair(s,name,pos,yaw=0,tape=False):
    g=s.group(name,pos,yaw,{'movable':True,'kind':'guest_chair'})
    g.rounded('BlackPolymer',(0,.466,0),(.465,.037,.425),.065,seg=6)
    # A gently curved molded back, open underneath as in the reference chairs.
    nx,ny=16,6;p=[];uv=[]
    for side in [-1,1]:
        for j in range(ny+1):
            t=j/ny;y=.61+t*.25
            for i in range(nx+1):
                u=i/nx*2-1;width=.205+.023*math.sin(t*math.pi/2)
                x=u*width;z=-.19-t*.075+.045*u*u+side*.008
                p.append([x,y-.025*u*u,z]);uv.append([i/nx,t])
    n=(nx+1)*(ny+1);f=[]
    for side in range(2):
        for j in range(ny):
            for i in range(nx):
                a=side*n+j*(nx+1)+i;ff=[[a,a+1,a+nx+2],[a,a+nx+2,a+nx+1]]
                if side==0:ff=[v[::-1] for v in ff]
                f.extend(ff)
    g.mesh('BlackPolymer',p,f,uv)
    # Thin edge strips seal the shell, avoiding doubled materials.
    edges=list(range(nx+1))+[j*(nx+1)+nx for j in range(1,ny+1)]+list(range(n-2,n-nx-2,-1))+[j*(nx+1) for j in range(ny-1,0,-1)]
    for i,a in enumerate(edges):
        b=edges[(i+1)%len(edges)];g.quad('BlackPolymer',[p[a],p[b],p[b+n],p[a+n]])
    for x in [-.214,.214]:
        g.tube('GreySteel',[(x*.99,.61,-.17),(x,.49,-.165),(x,.43,-.16),(x*1.18,.075,-.245)],.014,12)
        g.tube('GreySteel',[(x,.435,-.15),(x,.435,.15),(x*1.14,.075,.235)],.014,12)
        g.tube('BlackPolymer',[(x*.99,.61,-.17),(x*1.015,.695,-.19)],.016,12)
        for z in [-.245,.235]:
            xx=x*(1.18 if z<0 else 1.14)
            g.cyl('Rubber',(xx-.021,.039,z),(xx+.021,.039,z),.031,seg=12)
            g.cyl('BlackPolymer',(xx,.04,z),(xx,.077,z),.015,seg=10)
    if tape:
        # Two irregular strips of yellow tape, visible on the rear-facing chair.
        g.quad('YellowTape',[[-.025,.685,-.221],[.002,.69,-.221],[.092,.817,-.258],[.064,.82,-.258]])
        g.quad('YellowTape',[[.064,.82,-.259],[.092,.817,-.259],[.117,.739,-.237],[.094,.735,-.237]])
    g.collider(name+'_Seat',(0,.43,0),(.47,.10,.43));g.collider(name+'_Back',(0,.72,-.217),(.46,.30,.095));g.collider(name+'_Base',(0,.215,0),(.51,.43,.50))
    return g

def furniture(s):
    desk=s.group('Standing_Desk',(-.94,0,-.30),extras={'movable':True})
    desk.rounded('WhiteLaminate',(0,.77,0),(1.82,.028,.762),.012,seg=4)
    desk.box('GreySteel',(0,.712,0),(1.65,.055,.08))
    for x in [-.84,.84]:
        desk.rounded('GreySteel',(x,.025,0),(.095,.034,.68),.018,seg=4)
        desk.box('GreySteel',(x,.31,0),(.074,.56,.085));desk.box('GreySteel',(x,.627,0),(.064,.23,.073));desk.box('GreySteel',(x,.737,0),(.07,.025,.60))
        for z in [-.26,.26]:desk.cyl('Rubber',(x,.002,z),(x,.016,z),.023,seg=10)
        desk.collider('DeskLeg',(x,.38,0),(.09,.74,.11))
    desk.rounded('BlackPolymer',(.47,.735,.32),(.12,.025,.045),.008,3)
    desk.collider('DeskTop',(0,.764,0),(1.82,.04,.762))
    # Two white desktop power boxes; cables wrap closely around the edges
    # into an underside-mounted power strip, with no hanging loops.
    acc=s.group('Desk_Accessories',(-.94,0,-.30))
    acc.rounded('WhiteLaminate',(-.52,.806,.16),(.29,.042,.052),.009,3)
    for x in np.linspace(-.625,-.415,4):
        for z in [.151,.168]:acc.box('GreySteel',(float(x),.829,z),(.009,.003,.005))
    acc.rounded('WhiteLaminate',(-.12,.817,.30),(.17,.067,.115),.012,4)
    acc.box('WhiteLaminate',(-.12,.746,.405),(.035,.12,.026));acc.cyl('BlackPolymer',(-.12,.681,.397),(-.12,.72,.397),.007,seg=10)
    acc.rounded('WhiteLaminate',(-.35,.735,.075),(.29,.029,.068),.009,4)
    for x in [-.46,-.24]:acc.box('GreySteel',(x,.75,.075),(.015,.012,.084))
    for x in [-.43,-.35,-.27]:
        acc.box('GreySteel',(x,.718,.075),(.034,.004,.033))
    acc.box('BlackPolymer',(-.43,.729,.118),(.032,.025,.028))
    acc.box('WarmWhite',(-.27,.729,.118),(.032,.025,.028))
    acc.tube('Rubber',[(-.67,.808,.16),(-.82,.808,.16),(-.91,.80,.16),(-.925,.778,.16),(-.925,.75,.16),(-.91,.734,.16),(-.80,.734,.16),(-.60,.734,.15),(-.43,.731,.133)],.004,8)
    acc.tube('WarmWhite',[(-.12,.804,.35),(-.12,.802,.382),(-.12,.781,.399),(-.12,.752,.399),(-.12,.733,.382),(-.14,.733,.30),(-.23,.733,.21),(-.27,.731,.133)],.004,8)
    for x,z in [(-.80,.16),(-.60,.15),(-.14,.30),(-.23,.21)]:
        acc.box('WhiteLaminate',(x,.734,z),(.024,.012,.014))
    # Visitor-facing end = -.30 + .762/2 = +.081, flush with desk.
    tm=s.group('Walking_Treadmill',(-1.25,0,-.569),extras={'movable':True})
    tm.rounded('BlackPolymer',(0,.065,0),(.555,.12,1.30),.07,seg=6)
    tm.rounded('Rubber',(0,.131,.025),(.425,.009,1.04),.016,seg=3)
    for x in [-.25,.25]:
        tm.rounded('GreySteel',(x,.129,.035),(.033,.013,1.04),.012,4)
        tm.cyl('Orange',(x-.01,.056,.631),(x+.01,.056,.631),.016,seg=12)
    tm.box('BlackPolymer',(0,.142,-.557),(.31,.025,.115));tm.box('GreySteel',(0,.156,-.56),(.09,.003,.026))
    for j in range(4):tm.box('GreySteel',(-.09+j*.06,.158,-.583),(.026,.001,.002))
    tm.collider('Treadmill',(0,.07,0),(.555,.14,1.30))
    ch=s.group('Office_Chair',(-.52,0,-.76),extras={'movable':True})
    ch.rounded('BlueFabric',(0,.49,.02),(.49,.075,.47),.075,6)
    ch.rounded('BlackPolymer',(0,.442,0),(.42,.035,.39),.05,4)
    ch.cyl('Chrome',(0,.13,0),(0,.43,0),.025,seg=16)
    ch.cyl('BlackPolymer',(0,.25,0),(0,.435,0),.038,seg=16)
    for k in range(5):
        a=math.radians(18+k*72);x,z=math.cos(a)*.30,math.sin(a)*.30
        ch.cyl('GreySteel',(0,.17,0),(x,.085,z),.022,r2=.015,seg=12)
        ch.cyl('Rubber',(x-.029,.044,z),(x+.029,.044,z),.039,seg=14)
    for x in [-.30,.30]:
        ch.box('GreySteel',(x,.583,-.03),(.026,.24,.035));ch.rounded('ShelfPutty',(x,.708,-.005),(.10,.035,.255),.025,5)
    # Tilted woven back with a substantial frame, modelled as rounded horizontal bars.
    ch.box('GreySteel',(0,.63,-.225),(.065,.35,.04))
    ch.box('ChairMesh',(0,.874,-.245),(.435,.51,.018))
    for x in [-.226,.226]:ch.cyl('GreySteel',(x,.605,-.225),(x,1.145,-.268),.018,seg=12)
    for y,z in [(.614,-.225),(1.143,-.268)]:ch.cyl('GreySteel',(-.225,y,z),(.225,y,z),.018,seg=12)
    ch.rounded('BlackPolymer',(0,.71,-.265),(.31,.10,.035),.012,4)
    ch.collider('OfficeChairBase',(0,.25,0),(.62,.5,.62));ch.collider('OfficeChairBack',(0,.87,-.245),(.48,.56,.07))
    # Three-drawer mobile pedestal on the rear wall.
    cab=s.group('Filing_Cabinet',(.23,0,-1.37),-math.pi/2,extras={'movable':True})
    cab.box('WhiteLaminate',(0,.325,0),(.34,.58,.62))
    for yy,hh in [(.528,.13),(.385,.13),(.177,.26)]:
        cab.box('WhiteLaminate',(0,yy,.318),(.318,hh,.02));cab.cyl('Chrome',(-.10,yy+.022,.335),(.10,yy+.022,.335),.007,seg=10)
        for x in [-.10,.10]:cab.cyl('Chrome',(x,yy+.022,.325),(x,yy+.022,.349),.006,seg=8)
    for x in [-.12,.12]:
        for z in [-.25,.25]:cab.cyl('Rubber',(x-.018,.026,z),(x+.018,.026,z),.024,seg=10)
    cab.collider('FilingCabinet',(0,.31,0),(.35,.62,.66))
    table=s.group('Meeting_Table',(1.07,0,-.57),extras={'movable':True})
    table.cyl('MapleTable',(0,.723,0),(0,.753,0),.535,seg=72)
    table.cyl('BlackPolymer',(0,.09,0),(0,.72,0),.041,seg=20)
    table.cyl('BlackPolymer',(0,.70,0),(0,.724,0),.19,seg=24)
    for a in [0,math.pi/2,math.pi,3*math.pi/2]:
        x,z=math.cos(a)*.46,math.sin(a)*.46;table.cyl('BlackPolymer',(0,.085,0),(x,.035,z),.026,r2=.018,seg=12)
        table.cyl('Rubber',(x,.006,z),(x,.027,z),.023,seg=10)
    table.collider('TableTop',(0,.738,0),(1.07,.05,1.07),kind='cylinder');table.collider('TablePedestal',(0,.37,0),(.10,.72,.10))
    guest_chair(s,'Guest_Chair_Desk',(-.94,0,.60),math.pi)
    guest_chair(s,'Guest_Chair_Meeting_Left',(.43,0,-.80),1.23)
    guest_chair(s,'Guest_Chair_Meeting_Rear',(1.36,0,-1.26),-.40)
    guest_chair(s,'Guest_Chair_Meeting_Front',(1.16,0,.205),-3.026,True)
    sh=s.group('Bookcase',(-1.39,0,1.61),math.pi,{'movable':True})
    sh.box('ShelfInside',(0,.67,-.149),(.88,1.30,.018))
    for x in [-.444,.444]:sh.box('ShelfPutty',(x,.675,0),(.032,1.35,.32))
    for y in [.045,.325,1.085,1.335]:sh.box('ShelfPutty',(0,y,0),(.88,.025,.32))
    sh.box('ShelfPutty',(0,.034,.146),(.88,.065,.025))
    # Dark pinholes add the characteristic adjustable steel-shelf detail.
    for x in [-.426,.426]:
        for z in [-.105,.10]:
            for y in np.arange(.16,1.28,.032):sh.cyl('ShelfInside',(x,y,z),(x+(-.0006 if x>0 else .0006),y,z),.002,seg=6)
    sh.collider('Bookcase',(0,.675,0),(.92,1.35,.32))
    trash=s.group('Waste_Bin',(.22,0,.04),extras={'movable':True})
    # Open rectangular bin with a visible liner and folded paper contents.
    trash.rounded('BlackPolymer',(0,.04,0),(.26,.075,.32),.035,5)
    for x in [-.127,.127]:trash.box('BlackPolymer',(x,.235,0),(.016,.42,.33))
    for z in [-.158,.158]:trash.box('BlackPolymer',(0,.235,z),(.27,.42,.014))
    for x in [-.135,.135]:trash.rounded('BagLiner',(x,.44,0),(.023,.055,.35),.01,3)
    for z in [-.169,.169]:trash.rounded('BagLiner',(0,.44,z),(.28,.055,.024),.01,3)
    trash.quad('Cardboard',[[-.10,.29,-.08],[.03,.32,-.08],[.07,.40,.03],[-.08,.39,.04]])
    trash.quad('Cardboard',[[-.08,.39,.04],[.07,.40,.03],[.08,.31,.11],[-.04,.29,.12]])
    trash.quad('Cardboard',[[.0,.31,-.11],[.11,.30,-.08],[.10,.41,-.01],[.04,.42,-.02]])
    trash.collider('WasteBin',(0,.235,0),(.29,.47,.37))

def electrical(s):
    def outlet(name,pos,yaw):
        g=s.group(name,pos,yaw);g.rounded('WarmWhite',(0,0,0),(.073,.115,.009),.005,3)
        # Front face lies in XY; small socket slots are geometric.
        for y in [-.027,.027]:
            g.box('WhiteLaminate',(0,y,.007),(.043,.038,.005))
            for x in [-.011,.011]:g.box('GreySteel',(x,y+.004,.010),(.004,.012,.002))
            g.box('GreySteel',(0,y-.009,.010),(.005,.005,.002))
        return g
    outlet('Outlet_Rear',(-.90,.34,-D/2+.008),0)
    outlet('Outlet_Desk',(-W/2+.01,.30,-.54),math.pi/2)
    g=s.group('Wall_Controls',(W/2-.012,1.07,.68),-math.pi/2)
    g.box('WarmWhite',(0,0,0),(.075,.115,.011));g.box('GreySteel',(0,0,.009),(.016,.04,.007));g.box('WhiteLaminate',(0,.005,.017),(.009,.018,.012))
    g.box('Baseboard',(-.18,.012,.005),(.055,.082,.023));g.box('BlackPolymer',(-.18,.026,.018),(.032,.019,.002));g.box('WhiteLaminate',(-.18,-.008,.019),(.025,.023,.003))

def collision_scene(source):
    s=Scene();s.material('CollisionProxy',(50,210,160),.7)
    for i,c in enumerate(source.colliders):
        g=s.group(f"COL_{i:03d}_{c['name']}",c['parent_position'],c['parent_yaw_radians'],{'collision_only':True,'parent_visual':c['parent'],'shape':c['type']})
        if c['type']=='cylinder':
            x,y,z=c['center'];dx,dy,dz=c['size'];g.cyl('CollisionProxy',(x,y-dy/2,z),(x,y+dy/2,z),dx/2,seg=16)
        else:g.box('CollisionProxy',c['center'],c['size'],c['yaw_radians'])
    return s

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--output',type=Path,default=OUT);args=parser.parse_args();out=args.output;out.mkdir(parents=True,exist_ok=True)
    s=Scene();textures(s);materials(s);architecture(s);ceiling(s);furniture(s);electrical(s)
    stats=s.save(out/'office.glb');collision_scene(s).save(out/'office_collision.glb')
    (out/'colliders.json').write_text(json.dumps({'units':'metres','coordinate_system':'right-handed, Y up, +Z entry','colliders':s.colliders},indent=2))
    meta={'dimensions_m':{'width_measured':W,'depth_estimated':D,'height_estimated':H},'statistics':stats,'collider_count':len(s.colliders),'recommended_spawn_m':[.15,0,.85],'door_node':'Door_Hinge','door_open_y_degrees':-95,'assumptions':['12 ft 5 in interpreted as the maximum interior X width.','Depth and ceiling height estimated at 12 ft and 9 ft.','Rear-wall step, furniture dimensions, and positions estimated from photographs.','No hidden corridor or exterior geometry reconstructed.'],'texture_sizes':{'carpet':[1024,1024],'birch':[512,1024],'ceiling':[512,512],'chair_mesh':[128,128]}}
    (out/'asset_info.json').write_text(json.dumps(meta,indent=2));print(json.dumps(meta,indent=2))

if __name__=='__main__':main()
