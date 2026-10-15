local fs=require("@lune/fs")
local luau=require("@lune/luau")
local process=require("@lune/process")
local host_type=type
local host_tostring=tostring
local host_pairs=pairs
local host_ipairs=ipairs
local host_next=next
local host_pcall=pcall
local host_error=error
local host_rawset=rawset
local host_rawget=rawget
local host_setmetatable=setmetatable
local host_rawequal=rawequal
local host_getmetatable=getmetatable
local host_print=print
local host_table=table
local host_string=string
local input_path=process.args[1] or "input.luau"
local output_path=process.args[2] or "out.lua"
if input_path==output_path then host_error("input and output paths must be different",0) end
if not fs.isFile(input_path) then host_error("input file not found: "..input_path,0) end
local source=fs.readFile(input_path)
local events={}
local proxy_info=host_setmetatable({}, {__mode="k"})
local bootstrap_names={assert=true,error=true,ipairs=true,pairs=true,next=true,pcall=true,xpcall=true,select=true,tonumber=true,tostring=true,type=true,typeof=true,rawequal=true,rawget=true,rawset=true,setmetatable=true,getmetatable=true,getfenv=true,setfenv=true,unpack=true,load=true,loadstring=true,require=true,print=true,warn=true,wait=true,task=true,game=true,Game=true,workspace=true,Workspace=true,script=true,shared=true,_G=true,_VERSION=true,string=true,table=true,math=true,utf8=true,bit32=true,os=true,coroutine=true,debug=true,buffer=true,package=true,Vector2=true,Vector3=true,Vector2int16=true,Vector3int16=true,CFrame=true,Color3=true,ColorSequence=true,ColorSequenceKeypoint=true,UDim=true,UDim2=true,NumberRange=true,NumberSequence=true,NumberSequenceKeypoint=true,Rect=true,BrickColor=true,TweenInfo=true,Ray=true,RaycastParams=true,OverlapParams=true,PhysicalProperties=true,Random=true,DateTime=true,Font=true,Axes=true,Faces=true,Enum=true,Instance=true,Drawing=true,newproxy=true,makefolder=true,writefile=true,readfile=true,isfile=true,isfolder=true,listfiles=true,delfile=true,delfolder=true,appendfile=true,identifyexecutor=true,getexecutorname=true,getgenv=true,getrenv=true,checkcaller=true,hookfunction=true,hookmetamethod=true,getrawmetatable=true,setreadonly=true,cloneref=true,clonefunction=true,newcclosure=true,islclosure=true,iscclosure=true,isexecutorclosure=true,getgc=true,getconnections=true,getupvalue=true,getupvalues=true,getconstants=true,getsenv=true,getscripts=true,getrunningscripts=true,queue_on_teleport=true,queueonteleport=true,setfpscap=true,setclipboard=true,toclipboard=true,request=true,http_request=true,httpRequest=true,HttpRequest=true,getnamecallmethod=true,setnamecallmethod=true,gethiddenproperty=true,sethiddenproperty=true,gethui=true,getrenderproperty=true,setrenderproperty=true,isrenderobj=true,cleardrawcache=true,fireproximityprompt=true,firetouchinterest=true,firesignal=true,getscripthash=true,getthreadidentity=true,setthreadidentity=true,getidentity=true,setidentity=true,getthreadcontext=true,setthreadcontext=true,restorefunction=true,isrbxactive=true,isgameactive=true,queue_on_teleport=true,queueonteleport=true,readclipboard=true,writeclipboard=true}
local function record(kind,data)
 data.kind=kind
 data.id=#events+1
 host_table.insert(events,data)
 return data.id
end
local function mark_used(value)
 local info=proxy_info[value]
 if info and info.event_id and events[info.event_id] then events[info.event_id].skip=true end
end
local function format_value(value,seen,depth)
 local info=proxy_info[value]
 if info then
  mark_used(value)
  return info.path
 end
 local kind=host_type(value)
 if kind=="nil" then return "nil" end
 if kind=="string" then return host_string.format("%q",value) end
 if kind=="number" or kind=="boolean" then return host_tostring(value) end
 if kind=="function" then return "function(...) end" end
 if kind~="table" then return "nil" end
 if depth and depth>2 then return "{}" end
 seen=seen or {}
 if seen[value] then return "{}" end
 seen[value]=true
 local parts={}
 local count=0
 for key,item in host_pairs(value) do
  count+=1
  if count>8 then break end
  local key_text
  if host_type(key)=="string" and host_string.match(key,"^[%a_][%w_]*$") then
   key_text=key
  else
   key_text="["..format_value(key,seen,(depth or 0)+1).."]"
  end
  host_table.insert(parts,key_text.." = "..format_value(item,seen,(depth or 0)+1))
 end
 seen[value]=nil
 return "{"..host_table.concat(parts,", ").."}"
end
local function format_args(args,start_index)
 local parts={}
 for i=start_index or 1,args.n do host_table.insert(parts,format_value(args[i])) end
 return host_table.concat(parts,", ")
end
local proxy_mt={}
local function make_proxy(path,parent_path,key,event_id,object_type,typename)
 local value={}
 proxy_info[value]={path=path,parent_path=parent_path,key=key,event_id=event_id,object_type=object_type or "unknown",typename=typename}
 return host_setmetatable(value,proxy_mt)
end
local method_names={GetService=true,FindFirstChild=true,FindFirstChildOfClass=true,FindFirstChildWhichIsA=true,WaitForChild=true,GetChildren=true,GetDescendants=true,IsA=true,Clone=true,Destroy=true,ClearAllChildren=true,GetFullName=true,GetAttribute=true,SetAttribute=true,GetAttributes=true,GetPropertyChangedSignal=true,FindFirstAncestor=true,FindFirstAncestorOfClass=true,FindFirstAncestorWhichIsA=true,Connect=true,Once=true,Disconnect=true,Fire=true,FireServer=true,FireClient=true,FireAllClients=true,InvokeServer=true,InvokeClient=true,BindToRenderStep=true,UnbindFromRenderStep=true,GetPlayers=true,GetUserIdFromNameAsync=true,GetNameFromUserIdAsync=true,GetRoleInGroup=true,GetRankInGroup=true,GetMouse=true,GetPivot=true,PivotTo=true,MoveTo=true,TakeDamage=true,ChangeState=true,Play=true,Stop=true,Pause=true,Resume=true,Wait=true,Spawn=true,wait=true,spawn=true,defer=true,delay=true,cancel=true,wrap=true,create=true}
local scalar_types={Name="string",ClassName="string",DisplayName="string",UserId="number",AccountAge="number",Health="number",MaxHealth="number",WalkSpeed="number",JumpPower="number",Value="number",Text="string",Visible="boolean",Enabled="boolean",Archivable="boolean",AbsolutePosition="Vector2",AbsoluteSize="Vector2",Position="Vector3",Size="Vector3",CFrame="CFrame",Color="Color3",Transparency="number",CanCollide="boolean",Anchored="boolean",Material="EnumItem",Parent="Instance",Character="Instance",LocalPlayer="Instance",CurrentCamera="Instance",PrimaryPart="Instance",PlayerGui="Instance"}
local datatype_names={Vector3=true,Vector2=true,Vector2int16=true,Vector3int16=true,CFrame=true,Color3=true,ColorSequence=true,UDim=true,UDim2=true,NumberRange=true,Rect=true,BrickColor=true}
local function child_type(info,key)
 if info.object_type=="constructor" then
  if key=="new" then return "function" end
  return info.typename or "unknown"
 end
 if info.object_type=="enum" then return "EnumItem" end
 if info.object_type=="library" and method_names[key] then return "function" end
 if method_names[key] then return "function" end
 if info.object_type=="Instance" then return scalar_types[key] or "Instance" end
 return "unknown"
end
proxy_mt.__index=function(self,key)
 mark_used(self)
 local info=proxy_info[self]
 local suffix
 if host_type(key)=="string" and host_string.match(key,"^[%a_][%w_]*$") then
  suffix="."..key
 else
  suffix="["..format_value(key).."]"
 end
 local path=info.path..suffix
 local id=record("access",{path=path,code=path})
 return make_proxy(path,info.path,key,id,child_type(info,key),info.typename)
end
proxy_mt.__newindex=function(self,key,value)
 mark_used(self)
 local info=proxy_info[self]
 local path
 if host_type(key)=="string" and host_string.match(key,"^[%a_][%w_]*$") then
  path=info.path.."."..key
 else
  path=info.path.."["..format_value(key).."]"
 end
 record("statement",{code=path.." = "..format_value(value)})
end
proxy_mt.__call=function(self,...)
 mark_used(self)
 local info=proxy_info[self]
 local args=host_table.pack(...)
 local start_index=1
 local code
 if info.parent_path and args.n>0 then
  local first=proxy_info[args[1]]
  if first and first.path==info.parent_path then
   start_index=2
   mark_used(args[1])
   code=info.parent_path..":"..host_tostring(info.key).."("..format_args(args,start_index)..")"
  end
 end
 code=code or info.path.."("..format_args(args,start_index)..")"
 local id=record("call",{code=code,path=info.path})
 local result_type="unknown"
 if info.parent_path=="game" and info.key=="GetService" then
  result_type="Instance"
 elseif info.parent_path=="Instance" and info.key=="new" then
  result_type="Instance"
 elseif info.parent_path and datatype_names[info.parent_path] and info.key=="new" then
  result_type=info.parent_path
 elseif info.parent_path=="getgenv" or info.parent_path=="getrenv" or info.parent_path=="getfenv" then
  result_type="table"
 end
 return make_proxy(code,nil,nil,id,result_type)
end
proxy_mt.__tostring=function(self) return proxy_info[self].path end
proxy_mt.__eq=function(left,right)
 local a=proxy_info[left]
 local b=proxy_info[right]
 local code=format_value(left).." == "..format_value(right)
 record("expression",{code=code})
 return a~=nil and b~=nil and a.path==b.path
end
proxy_mt.__concat=function(left,right)
 local code=format_value(left).." .. "..format_value(right)
 local id=record("expression",{code=code})
 return make_proxy(code,nil,nil,id,"string")
end
local function binary(operator,left,right)
 local code=format_value(left).." "..operator.." "..format_value(right)
 local id=record("expression",{code=code})
 return make_proxy(code,nil,nil,id,"unknown")
end
proxy_mt.__add=function(a,b) return binary("+",a,b) end
proxy_mt.__sub=function(a,b) return binary("-",a,b) end
proxy_mt.__mul=function(a,b) return binary("*",a,b) end
proxy_mt.__div=function(a,b) return binary("/",a,b) end
proxy_mt.__idiv=function(a,b) return binary("//",a,b) end
proxy_mt.__mod=function(a,b) return binary("%",a,b) end
proxy_mt.__pow=function(a,b) return binary("^",a,b) end
proxy_mt.__unm=function(value)
 local code="-"..format_value(value)
 local id=record("expression",{code=code})
 return make_proxy(code,nil,nil,id,"number")
end
proxy_mt.__len=function(value)
 local code="#"..format_value(value)
 record("expression",{code=code})
 return 0
end
proxy_mt.__lt=function(a,b)
 local code=format_value(a).." < "..format_value(b)
 record("expression",{code=code})
 return false
end
proxy_mt.__le=function(a,b)
 local code=format_value(a).." <= "..format_value(b)
 record("expression",{code=code})
 return false
end
proxy_mt.__iter=function(value)
 local path=proxy_info[value].path
 mark_used(value)
 record("statement",{code="for _ in "..path.." do end"})
 return function() return nil end
end
proxy_mt.__metatable="locked"
local function make_library(name,library)
 local result={}
 local native_table_calls={pack=true,unpack=true,move=true,concat=true,insert=true,remove=true,clone=true,clear=true,freeze=true,create=true,find=true,sort=true,reverse=true}
 for key,value in host_pairs(library) do
  if host_type(value)=="function" then
   result[key]=(function(fn,method)
    return function(...)
     local args=host_table.pack(...)
     local code=name.."."..method.."("..format_args(args)..")"
     local has_proxy=false
     for i=1,args.n do
      if proxy_info[args[i]] then has_proxy=true break end
     end
     local id=record("call",{code=code})
     if has_proxy then
      if name=="table" and native_table_calls[method] and not proxy_info[args[1]] then return fn(...) end
      return make_proxy(code,nil,nil,id,"unknown")
     end
     return fn(...)
    end
   end)(value,key)
  else
   result[key]=value
  end
 end
 return result
end
local function output_call(name,...)
 local args=host_table.pack(...)
 local rendered={}
 for i=1,args.n do host_table.insert(rendered,format_value(args[i])) end
 local code=name.."("..host_table.concat(rendered,", ")..")"
 record("statement",{code=code})
 host_print(host_table.concat(rendered,"\t"))
end
local function sandbox_type(value)
 if proxy_info[value] then
  record("call",{code="type("..format_value(value)..")"})
  local kind=proxy_info[value].object_type
  if kind=="function" or kind=="string" or kind=="number" or kind=="boolean" then return kind end
  return "table"
 end
 return host_type(value)
end
local function sandbox_typeof(value)
 if proxy_info[value] then
  record("call",{code="typeof("..format_value(value)..")"})
  local result=proxy_info[value].object_type
  if result=="unknown" then return "table" end
  return result
 end
 return host_type(value)
end
local function sandbox_pairs(value)
 if proxy_info[value] then
  record("statement",{code="for _ in pairs("..format_value(value)..") do end"})
  return function() return nil end
 end
 return host_pairs(value)
end
local function sandbox_ipairs(value)
 if proxy_info[value] then
  record("statement",{code="for _ in ipairs("..format_value(value)..") do end"})
  return function() return nil end
 end
 return host_ipairs(value)
end
local function sandbox_next(value,...)
 if proxy_info[value] then
  record("call",{code="next("..format_value(value)..")"})
  return nil
 end
 return host_next(value,...)
end
local function sandbox_require(path)
 local code="require("..format_value(path)..")"
 local id=record("call",{code=code})
 return make_proxy(code,nil,nil,id,"table")
end
local function sandbox_loadstring(value)
 local code="loadstring("..format_value(value)..")"
 local id=record("call",{code=code})
 return make_proxy(code,nil,nil,id,"function")
end
local env={}
env.assert=assert
env.error=error
env.ipairs=sandbox_ipairs
env.pairs=sandbox_pairs
env.next=sandbox_next
env.pcall=pcall
env.xpcall=xpcall
env.select=select
env.tonumber=function(value,base)
 if proxy_info[value] then
  local code="tonumber("..format_value(value)..(base~=nil and ", "..format_value(base) or "")..")"
  local id=record("call",{code=code})
  return make_proxy(code,nil,nil,id,"number")
 end
 return tonumber(value,base)
end
env.tostring=function(value) if proxy_info[value] then record("call",{code="tostring("..format_value(value)..")"});return format_value(value) end return host_tostring(value) end
env.type=sandbox_type
env.typeof=sandbox_typeof
env.rawequal=function(a,b)
 if proxy_info[a] or proxy_info[b] then
  local left=format_value(a)
  local right=format_value(b)
  record("expression",{code="rawequal("..left..", "..right..")"})
  local first=proxy_info[a]
  local second=proxy_info[b]
  return first~=nil and second~=nil and first.path==second.path
 end
 return host_rawequal(a,b)
end
env.rawget=function(value,key)
 if proxy_info[value] or proxy_info[key] then
  local path=proxy_info[value] and proxy_info[value].path or "rawget_table"
  local index=format_value(key)
  local code="rawget("..format_value(value)..", "..index..")"
  mark_used(value)
  local id=record("call",{code=code})
  return make_proxy(proxy_info[value] and path.."["..index.."]" or code,nil,nil,id,"unknown")
 end
 return host_rawget(value,key)
end
env.rawset=function(value,key,item)
 if proxy_info[value] then
  local info=proxy_info[value]
  mark_used(value)
  record("statement",{code=info.path.."["..format_value(key).."] = "..format_value(item)})
  return value
 end
 return host_rawset(value,key,item)
end
env.setmetatable=function(value,meta)
 if proxy_info[value] then
  record("statement",{code="setmetatable("..format_value(value)..", "..format_value(meta)..")"})
  return value
 end
 return host_setmetatable(value,meta)
end
env.getmetatable=function(value)
 if proxy_info[value] then
  local code="getmetatable("..format_value(value)..")"
  local id=record("call",{code=code})
  return make_proxy(code,nil,nil,id,"table")
 end
 return host_getmetatable(value)
end
env.math=make_library("math",math)
env.string=make_library("string",string)
env.table=make_library("table",table)
env.utf8=make_library("utf8",utf8)
env.bit32=make_library("bit32",bit32)
env.unpack=env.table.unpack
env.print=function(...) output_call("print",...) end
env.warn=function(...) output_call("warn",...) end
env.require=sandbox_require
env.loadstring=sandbox_loadstring
env.load=sandbox_loadstring
env.getfenv=function(level)
 local code="getfenv("..format_value(level)..")"
 local id=record("call",{code=code})
 return make_proxy(code,nil,nil,id,"table")
end
env.setfenv=function(fn) record("statement",{code="setfenv("..format_value(fn)..", ...)"});return fn end
env.wait=make_proxy("wait",nil,nil,nil,"function")
env.task=make_proxy("task",nil,nil,nil,"library")
env._VERSION="Luau"
env.game=make_proxy("game",nil,nil,nil,"Instance")
env.Game=env.game
env.workspace=make_proxy("workspace",nil,nil,nil,"Instance")
env.Workspace=env.workspace
env.script=make_proxy("script",nil,nil,nil,"Instance")
env.Enum=make_proxy("Enum",nil,nil,nil,"enum")
for _,name in {"Instance","Vector2","Vector3","Vector2int16","Vector3int16","CFrame","Color3","ColorSequence","ColorSequenceKeypoint","UDim","UDim2","NumberRange","NumberSequence","NumberSequenceKeypoint","Rect","BrickColor","TweenInfo","Ray","RaycastParams","OverlapParams","PhysicalProperties","Random","DateTime","Font","Axes","Faces"} do
 env[name]=make_proxy(name,nil,nil,nil,"constructor",name)
end
env.shared=make_proxy("shared",nil,nil,nil,"table")
local function_names={newproxy=true,makefolder=true,writefile=true,readfile=true,isfile=true,isfolder=true,listfiles=true,delfile=true,delfolder=true,appendfile=true,identifyexecutor=true,getexecutorname=true,getgenv=true,getrenv=true,checkcaller=true,hookfunction=true,hookmetamethod=true,getrawmetatable=true,setreadonly=true,cloneref=true,clonefunction=true,newcclosure=true,islclosure=true,iscclosure=true,isexecutorclosure=true,getgc=true,getconnections=true,getupvalue=true,getupvalues=true,getconstants=true,getsenv=true,getscripts=true,getrunningscripts=true,queue_on_teleport=true,queueonteleport=true,setfpscap=true,setclipboard=true,toclipboard=true,request=true,http_request=true,httpRequest=true,HttpRequest=true,getnamecallmethod=true,setnamecallmethod=true,gethiddenproperty=true,sethiddenproperty=true,gethui=true,getrenderproperty=true,setrenderproperty=true,isrenderobj=true,cleardrawcache=true,fireproximityprompt=true,firetouchinterest=true,firesignal=true,getscripthash=true,getthreadidentity=true,setthreadidentity=true,getidentity=true,setidentity=true,getthreadcontext=true,setthreadcontext=true,restorefunction=true,isrbxactive=true,isgameactive=true,readclipboard=true,writeclipboard=true}
for name in bootstrap_names do
 if env[name]==nil then env[name]=make_proxy(name,nil,nil,nil,function_names[name] and "function" or "unknown") end
end
local function is_bootstrap_assignment(key,value)
 if not bootstrap_names[key] then return false end
 local info=proxy_info[value]
 if info then return info.path==key or key=="Game" and info.path=="game" or key=="Workspace" and info.path=="workspace" end
 local kind=host_type(value)
 if kind=="function" then return true end
 if kind=="table" and (key=="_G" or key=="string" or key=="table" or key=="math" or key=="utf8" or key=="bit32" or key=="os" or key=="coroutine" or key=="debug" or key=="buffer" or key=="package") then return true end
 return key=="_VERSION" and value=="Luau"
end
local globals=env
env={}
globals._G=env
proxy_info[env]={path="_G",object_type="table"}
setmetatable(env,{
 __index=function(_,key)
  local value=globals[key]
  if value~=nil then return value end
  local name=host_tostring(key)
  local id=record("access",{path=name,code=name})
  return make_proxy(name,nil,nil,id,"unknown")
 end,
 __newindex=function(_,key,value)
  if is_bootstrap_assignment(key,value) then return end
  local name=host_tostring(key)
  record("statement",{code=name.." = "..format_value(value)})
  globals[key]=value
 end
})
local run_ok,run_error=host_pcall(function()
 local chunk,load_error=luau.load(source,{debugName=input_path,environment=env,injectGlobals=false})
 if not chunk then host_error(load_error or "failed to load input",0) end
 chunk()
end)
local lines={}
local seen_access={}
local variable_count=0
for _,event in host_ipairs(events) do
 local code
 if event.kind=="access" and not event.skip then
  if not seen_access[event.code] then
   seen_access[event.code]=true
   variable_count+=1
   code="local v"..variable_count.." = "..event.code
  end
 elseif event.kind=="call" and not event.skip then
  variable_count+=1
  code="local v"..variable_count.." = "..event.code
 elseif event.kind=="expression" and not event.skip then
  variable_count+=1
  code="local v"..variable_count.." = "..event.code
 elseif event.kind=="statement" then
  code=event.code
 end
 if code and code~="" then host_table.insert(lines,code) end
end
fs.writeFile(output_path,host_table.concat(lines,"\n")..(#lines>0 and "\n" or ""))
if not run_ok then host_print("runtime error: "..host_tostring(run_error)) end
host_print("logged "..#events.." events")
host_print("written to "..output_path)
