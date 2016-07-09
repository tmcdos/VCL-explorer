unit Main;

interface

uses
  Windows, SysUtils, Classes, Controls, Forms, Dialogs, StdCtrls, ComCtrls,
  ExtCtrls, TntComCtrls, EnhListView, Buttons, ActnList, ImgList, ToolWin,
  VirtualTrees, Menus;

type
  TForm1 = class(TForm)
    Panel1: TPanel;
    OpenDialog1: TOpenDialog;
    nameParent: TLabeledEdit;
    img1: TImageList;
    actList1: TActionList;
    actImport: TAction;
    actLoad: TAction;
    actSave: TAction;
    vtClass: TVirtualStringTree;
    btnLoad: TBitBtn;
    btnImport: TBitBtn;
    btnSave: TBitBtn;
    edFilter: TLabeledEdit;
    findProc: TLabeledEdit;
    dlgSave1: TSaveDialog;
    popup1: TPopupMenu;
    actCopy: TAction;
    actCopy1: TMenuItem;
    procedure actCopyExecute(Sender: TObject);
    procedure actCopyUpdate(Sender: TObject);
    procedure actImportExecute(Sender: TObject);
    procedure actImportUpdate(Sender: TObject);
    procedure actLoadExecute(Sender: TObject);
    procedure actSaveExecute(Sender: TObject);
    procedure actSaveUpdate(Sender: TObject);
    procedure edFilterChange(Sender: TObject);
    procedure edFilterMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure FormCreate(Sender: TObject);
    procedure vtClassCompareNodes(Sender: TBaseVirtualTree; Node1, Node2: PVirtualNode; Column: TColumnIndex; var Result: Integer);
    procedure vtClassFocusChanged(Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex);
    procedure vtClassFreeNode(Sender: TBaseVirtualTree; Node: PVirtualNode);
    procedure vtClassGetText(Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType; var CellText: WideString);
    procedure vtClassLoadNode(Sender: TBaseVirtualTree; Node: PVirtualNode; Stream: TStream);
    procedure vtClassMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure vtClassSaveNode(Sender: TBaseVirtualTree; Node: PVirtualNode; Stream: TStream);
  private
    { Private declarations }
    Procedure AddUnitClass (n:PVirtualNode;t:AnsiString;idx:Integer); 
    Procedure BPL_load (f:TFileName); 
  public
    { Public declarations }
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

uses Dump, CommCtrl,Clipbrd;

procedure TForm1.actCopyExecute(Sender: TObject);
var
  data:PClassNode;
  s:AnsiString;
begin
  data:=vtClass.GetNodeData(vtClass.FocusedNode);
  s:='';
  Case data.kind Of
    ntGUID: s:=GUIDToString(data.gid);
    ntUnit,ntClass: s:=data.Txt;
    ntVProc,ntDProc,ntIProc: s:='('+IntToHex(data.ofs,4)+') '+data.Txt;
  end;
  if s<>'' Then
  with Clipboard do
  Begin
    Open;
    SetTextBuf(@s[1]);
    Close;
  end;
end;

procedure TForm1.actCopyUpdate(Sender: TObject);
begin
  TAction(Sender).Enabled:=Assigned(vtClass.FocusedNode);
end;

procedure TForm1.AddUnitClass(n:PVirtualNode;t:AnsiString;idx:Integer);
var
  node,Virt,Dyna:PVirtualNode;
  data:PClassNode;
  objInfo:TClass;
Begin
  node:=vtClass.AddChild(n);
  data:=vtClass.GetNodeData(node);
  data.Txt:=t;
  data.kind:=ntClass;
  objInfo:=Pointer(bpl.ExportList.Items[idx].MappedAddress);
  data.Ancestor:=GetAncestor(objInfo);
  Virt:=AddVirt(vtClass,node,objInfo);
  Dyna:=AddDyna(vtClass,node,objInfo);
  AddInter(vtClass,node,Virt,Dyna,objInfo);
  if node.ChildCount<>0 then vtClass.ReinitNode(node,False)
    Else vtClass.DeleteNode(node);
end;

procedure TForm1.BPL_load(f:TFileName);
var
  I,p:Integer;
  s:String;
  node:PVirtualNode;
  data:PClassNode;
  lst:TStringList;
Begin
  lst:=Nil;
  node:=Nil;
  if vtClass.RootNodeCount<>0 then
    if MessageDlg('Clear the tree before importing BPL ?',mtConfirmation,[mbYes,mbNo],0)=mrYes then vtClass.Clear;
  bpl.FileName:=f;
  bpl.ReadOnlyAccess:=True;
  vtClass.BeginUpdate;
  Screen.Cursor:=crHourGlass;
  try
    lst:=TStringList.Create;
    lst.Sorted:=False;
    for I:=0 to bpl.ExportList.FunctionCount-1 Do
    begin
      s:=bpl.ExportList.Items[I].Name;
      if (s[1]='@')And(s[Length(s)]='@') then
        lst.AddObject(uncode(s),Pointer(I));
    end;
    lst.Sort;
    s:='';
    for I:=0 to lst.Count-1 do
    begin
      p:=Pos('.',lst[I]);
      If s=Copy(lst[I],1,p-1) then AddUnitClass(node,Copy(lst[I],p+1,250),Integer(lst.Objects[I]))
      Else
      begin
        If Assigned(node) and (node.ChildCount=0) then vtClass.DeleteNode(node);
        s:=Copy(lst[I],1,p-1);
        node:=vtClass.AddChild(Nil);
        data:=vtClass.GetNodeData(node);
        data.Txt:=s;
        data.kind:=ntUnit;
        AddUnitClass(node,Copy(lst[I],p+1,250),Integer(lst.Objects[I]));
        vtClass.ReinitNode(node,False)
      end;
    end;
    If Assigned(node) And (node.ChildCount=0) then vtClass.DeleteNode(node);
  Finally
    lst.Free;
    Screen.Cursor:=crDefault;
    With vtClass do
    begin
      Header.SortColumn:=0;
      SortTree(0,sdAscending);
      EndUpdate;
      SetFocus;
    end;
  end;
  Caption:='VCL explorer - '+ExtractFileName(f);
  nameParent.Text:='';
  edFilter.Text:='';
end;

procedure TForm1.actImportExecute(Sender: TObject);
begin
  OpenDialog1.Filter:='BPL files|*.bpl|All files|*.*';
  if OpenDialog1.Execute Then BPL_load(OpenDialog1.FileName);
end;

procedure TForm1.actImportUpdate(Sender: TObject);
begin
  TAction(Sender).Enabled:=True;
end;

procedure TForm1.actLoadExecute(Sender: TObject);
begin
  OpenDialog1.Filter:='KB files|*.kb|All files|*.*';
  if OpenDialog1.Execute Then
  try
    Screen.Cursor:=crHourGlass;
    vtClass.LoadFromFile(OpenDialog1.FileName);
  Finally
    Screen.Cursor:=crDefault;
  end;
end;

procedure TForm1.actSaveExecute(Sender: TObject);
begin
  if dlgSave1.Execute Then
  try
    Screen.Cursor:=crHourGlass;
    vtClass.SaveToFile(dlgSave1.FileName);
  Finally
    Screen.Cursor:=crDefault;
  end;
end;

procedure TForm1.actSaveUpdate(Sender: TObject);
begin
  TAction(Sender).Enabled:=vtClass.RootNodeCount<>0;
end;

procedure TForm1.edFilterChange(Sender: TObject);
var
  P,S,Q:PVirtualNode;
  D,D2:PClassNode;
  v,empty:Boolean;
  s_trim,s_up,p_trim,p_up:AnsiString;
begin
  if vtClass.RootNodeCount=0 then Exit;
  s_trim:=Trim(edFilter.Text);
  s_up:=UpperCase(s_trim);
  p_trim:=Trim(FindProc.Text);
  p_up:=UpperCase(p_trim);
  empty:=(s_trim='')and(p_trim='');
  With vtClass Do
  try
    BeginUpdate;
    P:=RootNode.FirstChild;
    While Assigned(P) Do
    Begin
      if empty then IsVisible[P]:=True
      else
      begin
        D:=GetNodeData(P);
        Case D.kind Of
          ntClass: if s_trim<>'' then v:=Pos(s_up,UpperCase(D.Txt))>0 else v:=False;
          ntVProc,
          ntDProc:
            Begin
              Q:=P.Parent.Parent; // class node
              If p_trim='' then v:=IsVisible[Q]
              else
              Begin
                v:=Pos(p_up,UpperCase(D.Txt))>0;
                If v and (s_trim<>'') Then
                Begin
                  D2:=GetNodeData(Q);
                  // filtering on both class & method
                  v:=Pos(s_up,UpperCase(D2.Txt))>0;
                end;
              end;
            end;
          ntIProc:
            Begin
              Q:=P.Parent.Parent.Parent; // class node
              If p_trim='' then v:=IsVisible[Q]
              else
              Begin
                v:=Pos(p_up,UpperCase(D.Txt))>0;
                If v and (s_trim<>'') Then
                Begin
                  D2:=GetNodeData(Q);
                  // filtering on both class & method
                  v:=Pos(s_up,UpperCase(D2.Txt))>0;
                end;
              end;
            end;
          ntGUID:
            Begin
              Q:=P.Parent.Parent; // class node
              If p_trim='' then v:=IsVisible[Q]
              else
              Begin
                v:=Pos(p_up,GUIDToString(D.gid))>0;
                If v and (s_trim<>'') Then
                Begin
                  D2:=GetNodeData(Q);
                  // filtering on both class & method
                  v:=Pos(s_up,UpperCase(D2.Txt))>0;
                end;
              End;
            End;
        Else v:=False;
        end;
        IsVisible[P]:=v;
        if v Then
        Begin
          S:=P.Parent;
          While Assigned(S) and (S<>RootNode) and not IsVisible[S] Do
          Begin
            IsVisible[S]:=True;
            S:=S.Parent;
          end;
        end;
      End;
      P:=GetNext(P);
    end;
  Finally
    EndUpdate;
  End;
end;

procedure TForm1.edFilterMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  if TWinControl(Sender).CanFocus then ActiveControl:=TWinControl(Sender);
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  vtClass.NodeDataSize:=SizeOf(ClassNode);
end;

procedure TForm1.vtClassCompareNodes(Sender: TBaseVirtualTree; Node1, Node2: PVirtualNode; Column: TColumnIndex; var Result: Integer);
var
  D1,D2:PClassNode;
begin
  D1:=vtClass.GetNodeData(Node1);
  D2:=vtClass.GetNodeData(Node2);
  // 1st column shows names
  // 2nd column shows virtual offsets, dynamic IDs, interface offsets
  case D1.kind of
    ntGUID: Result:=lstrcmpA(PAnsiChar(GUIDToString(D1.gid)),PAnsiChar(GUIDToString(D2.gid)));
    ntVirtualGrp,
    ntDynamicGrp,
    ntInterfaceGrp:
      if D1.kind < D2.kind then Result:=-1
      else if D1.kind > D2.kind then Result:=1
      else Result:=0;
    ntVProc,
    ntIProc:
      if D1.ofs < D2.ofs then Result:=-1
      else if D1.ofs > D2.ofs then Result:=1
      else Result:=0;
    ntDProc:
      if Word(D1.ofs) < Word(D2.ofs) then Result:=1
      else if Word(D1.ofs) > Word(D2.ofs) then Result:=-1
      else Result:=0;
  else Result:=lstrcmpiA(PAnsiChar(D1.Txt),PAnsiChar(D2.Txt));
  end;
end;

procedure TForm1.vtClassFocusChanged(Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex);
var
  data:PClassNode;
begin
  if Assigned(node) Then
  Begin
    data:=Sender.GetNodeData(Node);
    nameParent.Text:=data.Ancestor;
  end
  else nameParent.Text:='';
end;

procedure TForm1.vtClassFreeNode(Sender: TBaseVirtualTree; Node: PVirtualNode);
var
  data:PClassNode;
begin
  data:=Sender.GetNodeData(Node);
  if Assigned(data) then Finalize(data^);
end;

procedure TForm1.vtClassGetText(Sender: TBaseVirtualTree; Node: PVirtualNode; Column: TColumnIndex; TextType: TVSTTextType; var CellText: WideString);
var
  data:PClassNode;
begin
  // 1st column shows - Units, Classes, Virtual/Dynamic/Interface groups, GUIDs
  // 2nd column shows - virtual offsets, dynamic IDs, interface offsets
  data:=Sender.GetNodeData(Node);
  case Column Of
    0:
      Case data.kind of
        ntGUID:
          CellText:=GUIDToString(data.gid);
        ntVirtualGrp:
          CellText:='('+IntToStr(Node.ChildCount)+') Virtual methods';
        ntDynamicGrp:
          CellText:='('+IntToStr(Node.ChildCount)+') Dynamic methods';
        ntInterfaceGrp:
          CellText:='('+IntToStr(Node.ChildCount)+') Interfaces';
      else CellText:=data.txt;
      End;
    1: if data.kind=ntDProc then CellText:=IntToHex(Word(data.ofs),4)
      else if data.kind in [ntVProc,ntIProc] then CellText:=IntToHex(data.ofs,4)
      Else CellText:='';
  end;
end;

procedure TForm1.vtClassLoadNode(Sender: TBaseVirtualTree; Node: PVirtualNode; Stream: TStream);
var
  data:PClassNode;
  n:Integer;
begin
  data:=Sender.GetNodeData(Node);
  with Stream, data^ do
  begin
    Read(ofs,SizeOf(ofs));
    Read(gid,SizeOf(gid));
    Read(kind,SizeOf(kind));
    Read(n,SizeOf(n));
    SetLength(Txt,n);
    Read(txt[1],n);
    Read(n,SizeOf(n));
    SetLength(Ancestor,n);
    Read(ancestor[1],n);
  end;
end;

procedure TForm1.vtClassMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  If vtClass.CanFocus then ActiveControl:=vtClass;
end;

procedure TForm1.vtClassSaveNode(Sender: TBaseVirtualTree; Node: PVirtualNode; Stream: TStream);
var
  data:PClassNode;
  n:Integer;
begin
  data:=Sender.GetNodeData(Node);
  with Stream, data^ do
  begin
    Write(ofs,SizeOf(ofs));
    Write(gid,SizeOf(gid));
    Write(kind,SizeOf(kind));
    n:=Length(Txt);
    Write(n,SizeOf(n));
    Write(txt[1],n);
    n:=Length(Ancestor);
    Write(n,SizeOf(n));
    Write(ancestor[1],n);
  end;
end;

end.

