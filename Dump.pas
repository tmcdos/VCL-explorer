unit Dump;

interface

Uses SysUtils,JclPeImage,VirtualTrees;

Type
  node_type = (ntUnit,ntClass,ntVirtualGrp,ntDynamicGrp,ntInterfaceGrp,ntVProc,ntDProc,ntIProc,ntGUID);
  ClassNode = Record
    Txt,Ancestor:AnsiString;
    ofs:Cardinal;
    gid:TGUID;
    kind:node_type;
  end;
  PClassNode = ^ClassNode;

var
  bpl:TJclPeImage;

function uncode(m:AnsiString):Ansistring;
Function GetAncestor(ClassTypeInfo: TClass):AnsiString;
function AddVirt(vt:TVirtualStringTree;n:PVirtualNode;ClassTypeInfo: TClass): PVirtualNode;
function AddDyna(vt:TVirtualStringTree;n:PVirtualNode;ClassTypeInfo: TClass): PVirtualNode;
procedure AddInter(vt:TVirtualStringTree;n,v,d:PVirtualNode;ClassTypeInfo: TClass);

implementation

Uses StrUtils,TypInfo,HVInterfaceMethods,HVVMT;

// convert image RVA into memory VA
function conv(adr:Pointer):Pointer; overload;
Begin
  Result:=bpl.RvaToVaEx(Cardinal(adr));
end;

// convert image RVA into memory VA
function conv(adr:Integer):Pointer; overload;
Begin
  Result:=bpl.RvaToVaEx(Cardinal(adr));
end;

// dumb unmangling for class names
function uncode(m:AnsiString):Ansistring;
Var
  i:Integer;
  ctr:Boolean;
  dtr:Boolean;
Begin
  ctr:=False;
  dtr:=False;
  i:=Pos('$',m);
  if i<>0 then
  begin
    if (m[i+1]='b')and(m[i+3]='t')and(m[i+4]='r')and(m[i+5]='$') then
    begin
      if m[i+2]='c' then ctr:=True
      else if m[i+2]='d' then dtr:=True;
    end;
    m:=Copy(m,1,i-1);
  end;
  if m[1]='@' then m[1]:=' ';
  i:=Length(m);
  if m[i]='@' then m[i]:=' ';
  Result:=Trim(AnsiReplaceStr(m,'@','.'));
  if ctr then Result:=Concat(Result,' = CONSTRUCTOR')
  else if dtr then Result:=Concat(Result,' = DESTRUCTOR');
end;

// find first class table after or equal to VMT entry - i.e. end of Virtual table
procedure Min(p_new,p_base:Pointer; var p_cur:Cardinal);
Begin
  if Cardinal(p_new)>=Cardinal(p_base) Then
    if Cardinal(p_new)<p_cur then p_cur:=Cardinal(p_new);
end;

// search inside Imported names
function imp_name(adr:Pointer):TJclPeImportFuncItem;
var
  I: Integer;
begin
  Result := nil;
  with bpl.ImportList do
    for I := 0 to AllItemCount - 1 do
      if adr=AllItems[I].RVA then
      begin
        Result := AllItems[I];
        Break;
      end;
end;

Function func_name(z:PAnsiChar):AnsiString;
var
  I:Integer;
  T:TJclPeExportFuncItem;
  N:TJclPeImportFuncItem;
Begin
  T:=Nil;
  for I:=0 to bpl.ExportList.FunctionCount-1 do
    If bpl.ExportList.Items[I].MappedAddress = Pointer(z) then
    begin
      T:=bpl.ExportList.Items[I];
      Break;
    End;
  If Assigned(T) then Result:=uncode(T.Name)
  Else if (z[0]=#255)and(z[1]=#$25) then
  begin
    N:=Nil;
    z:=conv(PInteger(z+2)^);
    for I:=0 to bpl.ImportList.AllItemCount-1 do
      If bpl.ImportList.AllItems[I].RVA = z then
      begin
        N:=bpl.ImportList.AllItems[I];
        Break;
      End;
    If Assigned(N) then Result:=uncode(N.Name)
      Else Result:='';
  end;
end;

Function intf_name(vt:TVirtualStringTree;n,v,d:PVirtualNode;adr:PAnsiChar):AnsiString;
var
  J:Cardinal;
  K:Integer;
  node:PVirtualNode;
  data:PClassNode;

  Procedure GetProc(m:PVirtualNode;X:Cardinal);
  Begin
    node:=m.FirstChild;
    While Assigned(node) do
    Begin
      data:=vt.GetNodeData(node);
      if data.ofs=X then
      Begin
        Result:='('+IntToHex(X,4)+') '+data.Txt;
        Break;
      end;
      node:=node.NextSibling;
    end;
  end;

Begin
  Result:='';

  if adr[0]=#5 then Inc(adr,5) // add eax,-IOffset
  Else if adr[0]=#$81 then Inc(adr,8) // add [esp+xx],-IOffset (dword)
  else if adr[0]=#$83 then
  begin
    if adr[1]=#$44 then Inc(adr,5) // add [esp+xx],-IOffset (byte)
    else if adr[1]=#$C0 then Inc(adr,3); // add eax,-IOffset (byte)
  end;
  If adr[0]=#$E9 then
  Begin
    // static method
    // 403EF599  0538FFFFFF  add	eax,FFFFFF38h
    // 403EF59E  E97D820000  jmp	@Xmldoc@TXMLDocument@GetDocumentObject$qqrv
    J:=PCardinal(adr+1)^ + Cardinal(adr) + 5;
    Result:=func_name(Pointer(J));
  end
  Else if (adr[0]=#$8B)and(adr[4]=#$8B)and(adr[6]=#255) Then
  Begin
    // virtual method
    // 403EF5AD  8144240438FFFFFF  add	dword ptr [esp+04h],FFFFFF38h
    // 403EF5B5  8B442404          mov	eax,[esp+04h]
    // 403EF5B9  8B00              mov	eax,[eax]
    // 403EF5BB  FF6028            jmp	[eax+28h]
      //// 403EF5BB  FFA0F0000000  jmp	[eax+F0h]
    if adr[7]=#$60 then K:=PShortInt(adr+8)^
    Else If adr[7]=#$A0 then K:=PInteger(adr+8)^
    else K:=-1;
    if (K>=0)and Assigned(v) then GetProc(v,Cardinal(K));
  end
  Else If (adr[0]=#$50)and(adr[1]=#$8B)and(adr[3]=#$8B) Then
  Begin
    // virtual method
    // 403EF5D8  0534FFFFFF   add	eax,FFFFFF34h
    // 403EF5DD  50           push	eax
    // 403EF5DE  8B00         mov	eax,[eax]
    // 403EF5E0  8B4030       mov	eax,[eax+30h]
      //// 403EF5E0  8B80A0000000   mov	eax,[eax+A0h]
    //// can be also MOV EAX,[EAX] instead of EAX+00h
    //// 403EF5E0  8B00         mov	eax,[eax]
    // 403EF5E3  870424       xchg	eax,[esp]
    // 403EF5E6  C3           retn
    If (adr[4]=#0)and(adr[8]=#$C3) then K:=0
    else If (adr[4]=#$40)and(adr[9]=#$C3) then K:=PShortInt(adr+5)^
    Else If (adr[4]=#$80)and(adr[12]=#$C3) then K:=PInteger(adr+5)^
    else K:=-1;
    if (K>=0)And Assigned(v) Then GetProc(v,Cardinal(K));
  end
  Else if (adr[0]=#$50)and(adr[1]=#$52)and(adr[2]=#$51)and(adr[3]=#$66)and(adr[17]=#$C3) Then
  Begin
    // dynamic method
    // 403EF77C  0534FFFFFF   add	eax,FFFFFF34h
    // 403EF781  50           push	eax
    // 403EF782  52           push	edx
    // 403EF783  51           push	ecx
    // 403EF784  66BAE7FF     mov	dx,FFE7h
    // 403EF788  E8FB18F8FF   call	jmp_rtl70.bpl!@System@@FindDynaInst$qqrv
    // 403EF78D  59           pop	ecx
    // 403EF78E  5A           pop	edx
    // 403EF78F  870424       xchg	eax,[esp]
    // 403EF792  C3           retn
    if Assigned(d) Then GetProc(d,PWord(adr+5)^);
  end;
end;

Function GetAncestor(ClassTypeInfo: TClass):AnsiString;
var
  ClassVMT:PVmt;
  p:Pointer;
Begin
  Result:='';
  ClassVMT:=GetVmt(ClassTypeInfo);
  if Assigned(ClassVMT.Parent) then
  begin
    // first check if this class is imported from other BPL
    p:=conv(Pointer(PInteger(conv(ClassVMT.Parent))^));
    if Assigned(p) and (PWord(p)^=0) then Result:=uncode(PAnsiChar(p)+2)
    else if conv(ClassVMT.Parent)<>NIL Then
      // local class
      Result:=PShortString(conv(PVmt(conv(ClassVMT.Parent))^.ClassName))^;
  end;
end;

Function AddVirt(vt:TVirtualStringTree;n:PVirtualNode;ClassTypeInfo: TClass):PVirtualNode;
Var
  ClassVMT:PVmt;
  i,vmt: Cardinal;
  p:Pointer;
  vptr:PInteger;
  node:PVirtualNode;
  data:PClassNode;
  s:AnsiString;
Begin
  ClassVMT:=GetVmt(ClassTypeInfo);
  // compute count of virtual methods - first find the smallest address
  // from VMT tables, then subtract VMTptr from it and divide result by 4
  vptr:=Pointer(ClassVMT.SelfPtr);
  vmt:=Cardinal(Pointer(ClassVMT.ClassName));
  Min(ClassVMT.IntfTable,vptr,vmt);
  Min(ClassVMT.AutoTable,vptr,vmt);
  Min(ClassVMT.InitTable,vptr,vmt);
  Min(ClassVMT.TypeInfo,vptr,vmt);
  Min(ClassVMT.FieldTable,vptr,vmt);
  Min(ClassVMT.MethodTable,vptr,vmt);
  Min(ClassVMT.DynamicTable,vptr,vmt);
  vmt:=(vmt - Cardinal(vptr)) div SizeOf(Pointer);
  // enumerate virtual methods
  Result:=Nil;
  if vmt<>0 then
  begin
    n:=vt.AddChild(n);
    data:=vt.GetNodeData(n);
    data.kind:=ntVirtualGrp;
    for i := 0 to vmt-1 do
    begin
      // exported addresses are relative to ImageBase
      if bpl.ExportList.ItemFromAddress[PCardinal(conv(vptr))^-bpl.OptionalHeader.ImageBase]<>nil then
        s:=bpl.ExportList.ItemFromAddress[PCardinal(conv(vptr))^-bpl.OptionalHeader.ImageBase].Name
      else
      begin
        p:=conv(Pointer(vptr)); // get VMT entry
        p:=conv(Pointer(PInteger(p)^)); // get value of VMT entry
        // this is "trampoline" stub - JMP
        if PWord(p)^=$25FF then p:=conv(Pointer(PInteger(PChar(p)+2)^));
        p:=conv(Pointer(PInteger(p)^));
        s:=PAnsiChar(PAnsiChar(p)+2);
        //if imp_name(p)<>NIL Then n:=imp_name(p).Name
          //else n:='unknown';
      end;
      node:=vt.AddChild(n);
      data:=vt.GetNodeData(node);
      data.kind:=ntVProc;
      data.ofs:=i*4;
      data.Txt:=uncode(s);
      Inc(vptr);
    End;
    vt.ReinitNode(n,True);
    Result:=n;
  end;
end;

Function AddDyna(vt:TVirtualStringTree;n:PVirtualNode;ClassTypeInfo: TClass):PVirtualNode;
Var
  ClassVMT,curClass:PVmt;
  dynTable: PDmt;
  i: Cardinal;
  dyn:PDmtMethods;
  node:PVirtualNode;
  data:PClassNode;
Begin
  ClassVMT:=GetVmt(ClassTypeInfo);
  Result:=Nil;
  // enumerate dynamic methods - including all parent classes
  curClass:=ClassVMT;
  while True Do
  begin
    if Assigned(curClass.DynamicTable) Then
    Begin
      dynTable:=conv(curClass.DynamicTable);
      if dynTable.Count<>0 then
      begin
        if Not Assigned(Result) Then
        Begin
          Result:=vt.AddChild(n);
          data:=vt.GetNodeData(Result);
          data.kind:=ntDynamicGrp;
        end;
        dyn:=Pointer(Cardinal(@dynTable.Indicies)+dynTable.Count*SizeOf(TDMTIndex));
        for i:=0 to dynTable.Count-1 Do
        Begin
          node:=vt.AddChild(Result);
          data:=vt.GetNodeData(node);
          data.kind:=ntDProc;
          data.ofs:=Word(dynTable.Indicies[i]);
          // dynamic methods are always local - i.e. exported
          if bpl.ExportList.ItemFromAddress[Cardinal(dyn^[i])-bpl.OptionalHeader.ImageBase]<>nil then
            data.Txt:=uncode(bpl.ExportList.ItemFromAddress[Cardinal(dyn^[i])-bpl.OptionalHeader.ImageBase].Name)
          else data.Txt:='unknown';
        end;
      End;
    end;
    // stop when reach imported parent or parent is NIL
    if curClass.Parent=NIL then Break;
    curClass:=conv(curClass.Parent);
    if Cardinal(curClass.SelfPtr) < bpl.OptionalHeader.ImageBase then Break;
  End;
end;

Procedure AddInter(vt:TVirtualStringTree;n,v,d:PVirtualNode;ClassTypeInfo: TClass);
Var
  ClassVMT:PVmt;
  i,j: Cardinal;
  tmp:Pointer;
  vptr:PInteger;
  intf:PInterfaceTable;
  node,grp,grp2:PVirtualNode;
  data:PClassNode;
Begin
  ClassVMT:=GetVmt(ClassTypeInfo);
  // enumerate interfaces
  if Assigned(ClassVMT.IntfTable) Then
  Begin
    intf:=conv(ClassVMT.IntfTable);
    vptr:=Pointer(intf);
    for i:=0 to intf.EntryCount-1 do
    begin
      tmp:=conv(intf.Entries[I].VTable);
      if Cardinal(tmp) < Cardinal(vptr) then vptr:=tmp;
    End;
    j:=0;
    while vptr <> Pointer(intf) do
    Begin
      if Not Assigned(grp) Then
      Begin
        grp:=vt.AddChild(n);
        data:=vt.GetNodeData(grp);
        data.kind:=ntInterfaceGrp;
      end;
      for i:=0 to intf.EntryCount-1 do
        if vptr = conv(intf.Entries[I].VTable) then
        begin
          grp2:=vt.AddChild(grp);
          data:=vt.GetNodeData(grp2);
          data.kind:=ntGUID;
          data.gid:=intf.Entries[i].IID;
          j:=0;
        end;
      node:=vt.AddChild(grp2);
      data:=vt.GetNodeData(node);
      data.kind:=ntIProc;
      data.ofs:=j;
      data.Txt:=intf_name(vt,n,v,d,conv(vptr^));
      Inc(j,4);
      Inc(vptr);
    end;
  end;
end;

Initialization
  bpl:=TJclPeImage.Create;

Finalization
  bpl.Free;

end.
