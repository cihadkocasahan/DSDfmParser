unit DS.DfmParser;

interface

uses
   System.SysUtils, System.Classes, System.Generics.Collections, CommonTypes, strutils;

type
   EDfmParseInvalidFormat = class(Exception);

   TDfmObject = class;

   TDfmProperty = class(TPersistent)
   strict private
      FOwner: TDfmObject;
      FName: string;
      FValue: string;
   public
      constructor Create(AOwner: TDfmObject; const AName, AValue: string);
      procedure Assign(Source: TPersistent); override;
      property Owner: TDfmObject read FOwner;
      property Name: string read FName write FName;
      property Value: string read FValue write FValue;
   end;

   TDfmObjectList = class(TObjectList<TDfmObject>)
      type
         TNames = TObjectDictionary<string, TDfmObject>;
   strict private
      FNames: TNames;
   protected
      procedure DoNotify(Sender: TObject; const Item: TDfmObject; Action: TCollectionNotification);
   public
      constructor Create;
      destructor Destroy; override;
      function GetObject(const AName: string): TDfmObject;
      property Names: TNames read FNames;
   end;

   TDfmObjectType = (doObject, doInherited, doInline);

   TDfmPropertyList = class(TObjectList<TDfmProperty>)
      type
         TNames = TObjectDictionary<string, TDfmProperty>;
   strict private
      FNames: TNames;
   protected
      procedure DoNotify(Sender: TObject; const Item: TDfmProperty; Action: TCollectionNotification);
   public
      constructor Create;
      destructor Destroy; override;
      function GetProperty(const AName: string): TDfmProperty;
      property Names: TNames read FNames;
   end;

   TDfmObject = class(TObject)
   strict private
      FOwner: TDfmObject;
      FName: string;
      FClassName: string;
      FId: Integer;
      FProperties: TDfmPropertyList;
      FObjects: TDfmObjectList;
      FObjectType: TDfmObjectType;
   private
      FClassSaved: string;
      FPropertiesSaved: TObjectList<TDfmProperty>;
      FObjectsSaved: TObjectList<TDfmObject>;
   public
      constructor Create(const AOwner: TDfmObject; const AName: string);
      destructor Destroy; override;
      function HasProperty(const APropertyName: string): Boolean; overload;
      function HasProperty(const APropertyName, AValue: string): Boolean; overload;
      function GetProperty(const APropertyName: string): string;
      function HasObject(const AName: string): Boolean;
      function GetObject(const AName: string; const ARecursive: Boolean = False): TDfmObject;
      property Owner: TDfmObject read FOwner;
      property Name: string read FName write FName;
      property ClassName_: string read FClassName write FClassName;
      property Id: Integer read FId write FId;
      property ObjectType: TDfmObjectType read FObjectType write FObjectType;
      property Properties: TDfmPropertyList read FProperties;
      property Objects: TDfmObjectList read FObjects;
   end;

   TDfmFile = class(TDfmObject)
   strict private
      procedure Parse(const ADfmContent: string);
   public
      constructor Create; overload;
      procedure Save(const AFileName: string);
      procedure LoadFromFile(const AFileName: string);
      procedure LoadFromString(const ADfmContent: string);
      function GetDfm: string;
   end;

   TDprFile = class(TDfmObject)
      FPath: string;
   strict private
      procedure Parse(const ADfmContent: string);
   public
      constructor Create; overload;
      procedure LoadFromFile(const AFileName: string);
      procedure LoadFromString(const ADfmContent: string);
      class function IsValidDfm(const AFileName: string): Boolean;
   end;

function RemoveUnicodestr(Str: string): string;

function LoadPropList: TStrings;

implementation

uses
   System.IOUtils, System.RegularExpressions;

const
   CR = #13;
   LF = #10;
   CRLF = #13#10;

{ TDfmObject }

constructor TDfmObject.Create(const AOwner: TDfmObject; const AName: string);
begin
   inherited Create;
   FOwner := AOwner;
   FName := AName;
   FId := -1;
   if FOwner <> nil then
   begin
      FOwner.Objects.Add(Self);
   end;
   FProperties := TDfmPropertyList.Create;
   FObjects := TDfmObjectList.Create;
   FPropertiesSaved := TObjectList<TDfmProperty>.Create;
   FObjectsSaved := TObjectList<TDfmObject>.Create;
end;

destructor TDfmObject.Destroy;
begin
   FreeAndNil(FObjects);
   FreeAndNil(FProperties);
   FreeAndNil(FPropertiesSaved);
   FreeAndNil(FObjectsSaved);
   inherited;
end;

function LoadPropList: TStrings;
begin
   Result := TStringList.Create;
   if FileExists('proplist.txt') then
      Result.LoadFromFile('proplist.txt')
   else
   begin
      Result.Add('Caption');
      Result.Add('Text');
      Result.Add('DisplayLabel');
      Result.Add('Hint');
      Result.Add('Title');
   end;
end;

function TDfmObject.GetObject(const AName: string; const ARecursive: Boolean): TDfmObject;

   function Search(const DfmObjectParent: TDfmObject; const Name: string): TDfmObject;
   var
      DfmChildObject: TDfmObject;
      DfmObject: TDfmObject;
   begin
      if DfmObjectParent.Name = Name then
      begin
         Result := DfmObjectParent;
         Exit;
      end;
      for DfmChildObject in DfmObjectParent.Objects do
      begin
         DfmObject := Search(DfmChildObject, Name);
         if DfmObject <> nil then
         begin
            Result := DfmObject;
            Exit;
         end;
      end;
      Result := nil;
   end;

var
   DfmObject: TDfmObject;
begin
   if ARecursive then
   begin
      Result := Search(Self, AName);
   end
   else
   begin
      for DfmObject in Objects do
      begin
         if DfmObject.Name.ToLower = AName.ToLower then
         begin
            Result := DfmObject;
            Exit;
         end;
      end;
      Result := nil;
   end;
end;

function TDfmObject.GetProperty(const APropertyName: string): string;
var
   DfmProperty: TDfmProperty;
begin
   DfmProperty := Properties.GetProperty(APropertyName);
   if DfmProperty = nil then
   begin
      Result := EmptyStr;
   end
   else
   begin
      Result := DfmProperty.Value;
   end;
end;

function TDfmObject.HasObject(const AName: string): Boolean;
var
   DfmObject: TDfmObject;
begin
   for DfmObject in Objects do
   begin
      if DfmObject.Name.ToLower = AName.ToLower then
      begin
         Result := True;
         Exit;
      end;
   end;
   Result := False;
end;

function TDfmObject.HasProperty(const APropertyName, AValue: string): Boolean;
var
   objDfmProperty: TDfmProperty;
begin
   Result := Properties.Names.TryGetValue(APropertyName.ToLower, objDfmProperty) and (objDfmProperty.Value = AValue);
end;

function TDfmObject.HasProperty(const APropertyName: string): Boolean;
begin
   Result := Properties.Names.ContainsKey(APropertyName.ToLower);
end;

{ TDfmFile }

procedure TDfmFile.Parse(const ADfmContent: string);
var
   Lines: TStringList;
   LineNumber: Integer;
   LineCount: Integer;
   LineContent: string;
   Value: string;
   RegExObject: TRegEx;
   RegExProperty: TRegEx;
   Match: TMatch;
   objDfmObject: TDfmObject;

   function GetLine(ATrim: Boolean = True): string;
   begin
      if ATrim then
      begin
         Result := Lines[LineNumber].Trim;
      end
      else
      begin
         Result := Lines[LineNumber].Trim.TrimRight([#13]);
      end;
      Inc(LineNumber);
   end;

var
   Depth: Integer;
   Name: string;
   ClassName: string;
   Id: Integer;
begin
   if not ADfmContent.StartsWith('object', True) and not ADfmContent.StartsWith('inherited', True) and not ADfmContent.StartsWith('inline', True) then
   begin
      raise EDfmParseInvalidFormat.Create('Invalid dfm file!');
   end;
   Self.Name := EmptyStr;
   Self.ClassName_ := EmptyStr;
   Self.Id := 0;
   Properties.Clear;
   Objects.Clear;
   objDfmObject := nil;

   RegExObject := TRegEx.Create('^(\w+) (?:([\w\däöü_]+): )?([\w\d_]+)(?: \[(\d+)\])?$', [roIgnoreCase]);
   RegExProperty := TRegEx.Create('^([\w\d_\.]+) =(?:(?: (.*)$)|$)', [roIgnoreCase]);
   Lines := TStringList.Create;
   try
      Lines.Delimiter := LF;
      Lines.Text := ADfmContent;
      LineCount := Lines.Count;
      LineNumber := 0;

      while LineNumber < LineCount do
      begin
         LineContent := GetLine;

      // object
         Match := RegExObject.Match(LineContent);
         if Match.Success then
         begin
            Name := EmptyStr;
            ClassName := EmptyStr;
            Id := -1;
            if Match.Groups.Count = 5 then
            begin
               Name := Match.Groups[2].Value;
               ClassName := Match.Groups[3].Value;
               Id := Match.Groups[4].Value.ToInteger;
            end
            else if Match.Groups.Count = 4 then
            begin
               Name := Match.Groups[2].Value;
               ClassName := Match.Groups[3].Value;
            end
            else if Match.Groups.Count = 3 then
            begin
               Name := EmptyStr;
               ClassName := Match.Groups[2].Value;
            end;

            if objDfmObject = nil then
            begin
               objDfmObject := Self;
               objDfmObject.Name := Name;
            end
            else
            begin
               objDfmObject := TDfmObject.Create(objDfmObject, Name);
            end;
            objDfmObject.ClassName_ := ClassName;
            objDfmObject.Id := Id;

            if Match.Groups[1].Value.ToLower = 'object' then
            begin
               objDfmObject.ObjectType := doObject;
            end
            else if Match.Groups[1].Value.ToLower = 'inherited' then
            begin
               objDfmObject.ObjectType := doInherited;
            end
            else if Match.Groups[1].Value.ToLower = 'inline' then
            begin
               objDfmObject.ObjectType := doInline;
            end
            else
            begin
          //prcLog(Self, 'Unknown DFM Object type "' + objMatch.Groups[1].Value + '"!', lpError);
               Exit;
            end;
            objDfmObject.FClassSaved := objDfmObject.ClassName_;
            Continue;
         end;

      // property
         Match := RegExProperty.Match(LineContent);
         if Match.Success then
         begin
            if objDfmObject <> nil then
            begin
               if (Match.Groups.Count > 2) and Match.Groups[2].Success then
               begin
                  Value := Match.Groups[2].Value;
               end
               else
               begin
                  Value := EmptyStr;
               end;
               if Value = '(' then
               begin
                  Value := Value + CRLF;
                  repeat
                     Value := Value + GetLine(False) + CRLF;
                  until Value.Substring(Value.Length - 3, 1) = ')';
                  Value := Value.TrimRight;
               end
               else if Value = '{' then
               begin
                  Value := Value + CRLF;
                  repeat
                     Value := Value + GetLine(False) + CRLF;
                  until Value.Substring(Value.Length - 3, 1) = '}';
                  Value := Value.TrimRight;
               end
               else if Value = '<' then
               begin
                  Depth := 1;
                  Value := Value + CRLF;
                  repeat
                     Value := Value + GetLine(False) + CRLF;
                     if Value.Substring(Value.Length - 4, 2) <> '<>' then
                     begin
                        if Value.Substring(Value.Length - 3, 1) = '<' then
                        begin
                           Inc(Depth);
                        end
                        else if Value.Substring(Value.Length - 3, 1) = '>' then
                        begin
                           Dec(Depth);
                        end;
                     end;
                  until Depth = 0;
                  Value := Value.TrimRight;
               end
               else if Value = EmptyStr then
               begin
                  Value := Value + CRLF;
                  repeat
                     Value := Value + GetLine(False) + CRLF;
                  until Value.Substring(Value.Length - 3, 1) <> '+';
                  Value := Value.TrimRight;
               end;

               TDfmProperty.Create(objDfmObject, Match.Groups[1].Value, Value);
            end
            else
            begin
          //prcLog(Self, 'Can''t assign DFM-Property! No object available!', lpError);
               Exit;
            end;
            Continue;
         end;

      // end
         if LineContent = 'end' then
         begin
            if objDfmObject <> nil then
            begin
               objDfmObject := objDfmObject.Owner;
            end;
            Continue;
         end;
      end;
   finally
      FreeAndNil(Lines);
   end;
end;

function TDfmFile.GetDfm: string;
var
   DFM: string;

   procedure RenderWhitespace(const ADepth: Integer);
   begin
      DFM := DFM + EmptyStr.PadLeft(ADepth * 2);
   end;

   procedure RenderProperty(const ADfmProperty: TDfmProperty; const ADepth: Integer);
   begin
      RenderWhitespace(ADepth);
      DFM := DFM + ADfmProperty.Name + ' = ' + ADfmProperty.Value + CRLF;
   end;

   procedure RenderObject(const ADfmObject: TDfmObject; const ADepth: Integer);
   var
      objDfmProperty: TDfmProperty;
      objDfmObjectChild: TDfmObject;
   begin
      RenderWhitespace(ADepth);
      case ADfmObject.ObjectType of
         doObject:
            DFM := DFM + 'object ';
         doInherited:
            DFM := DFM + 'inherited ';
         doInline:
            DFM := DFM + 'inline ';
      end;
      if ADfmObject.Name <> EmptyStr then
      begin
         DFM := DFM + ADfmObject.Name + ': ';
      end;
      DFM := DFM + ADfmObject.ClassName_;
      if ADfmObject.Id >= 0 then
      begin
         DFM := DFM + ' [' + ADfmObject.Id.ToString + ']';
      end;
      DFM := DFM + CRLF;
      for objDfmProperty in ADfmObject.Properties do
      begin
         RenderProperty(objDfmProperty, ADepth + 1);
      end;
      for objDfmObjectChild in ADfmObject.Objects do
      begin
         RenderObject(objDfmObjectChild, ADepth + 1);
      end;
      RenderWhitespace(ADepth);
      DFM := DFM + 'end' + CRLF;
   end;

begin
   RenderObject(Self, 0);
   Result := DFM;
end;

constructor TDfmFile.Create;
begin
   inherited Create(nil, EmptyStr);
end;

procedure TDfmFile.Save(const AFileName: string);
var
   Lines: TStringList;
begin
   Lines := TStringList.Create;
   try
      Lines.Text := GetDfm;
      Lines.SaveToFile(AFileName);
   finally
      FreeAndNil(Lines);
   end;
end;

procedure TDfmFile.LoadFromFile(const AFileName: string);
begin
   Parse(TFile.ReadAllText(AFileName));
end;

procedure TDfmFile.LoadFromString(const ADfmContent: string);
begin
   Parse(ADfmContent);
end;

{ TDfmProperty }

procedure TDfmProperty.Assign(Source: TPersistent);
var
   DfmProperty: TDfmProperty;
begin
   if Source is TDfmProperty then
   begin
      DfmProperty := Source as TDfmProperty;
      FOwner := DfmProperty.Owner;
      FName := DfmProperty.Name;
      FValue := DfmProperty.Value;
   end
   else
   begin
      inherited;
   end;
end;

constructor TDfmProperty.Create(AOwner: TDfmObject; const AName, AValue: string);
begin
   inherited Create;
   FOwner := AOwner;
   FName := AName;
   FValue := AValue;
   FOwner.Properties.Add(Self);
end;

{ TDfmObject.TDfmObjectList }

constructor TDfmObjectList.Create;
begin
   inherited Create(True);
   FNames := TNames.Create;
   OnNotify := DoNotify;
end;

destructor TDfmObjectList.Destroy;
begin
   FreeAndNil(FNames);
   inherited;
end;

function TDfmObjectList.GetObject(const AName: string): TDfmObject;
begin
   if not FNames.TryGetValue(AName.ToLower, Result) then
   begin
      Result := nil;
   end;
end;

procedure TDfmObjectList.DoNotify(Sender: TObject; const Item: TDfmObject; Action: TCollectionNotification);
begin
   if (FNames <> nil) and (Item.Name <> EmptyStr) then
   begin
      case Action of
         cnAdded:
            FNames.AddOrSetValue(Item.Name.ToLower, Item);
         cnRemoved, cnExtracted:
            FNames.Remove(Item.Name.ToLower);
      end;
   end;
end;

{ TDfmObject.TDfmPropertyList }

constructor TDfmPropertyList.Create;
begin
   inherited Create(True);
   FNames := TNames.Create;
   OnNotify := DoNotify;
end;

destructor TDfmPropertyList.Destroy;
begin
   FreeAndNil(FNames);
   inherited;
end;

function TDfmPropertyList.GetProperty(const AName: string): TDfmProperty;
begin
   if not Names.TryGetValue(AName.ToLower, Result) then
   begin
      Result := nil;
   end;
end;

procedure TDfmPropertyList.DoNotify(Sender: TObject; const Item: TDfmProperty; Action: TCollectionNotification);
begin
   if (Names <> nil) and (Item.Name <> EmptyStr) then
   begin
      case Action of
         cnAdded:
            Names.AddOrSetValue(Item.Name.ToLower, Item);
         cnRemoved, cnExtracted:
            Names.Remove(Item.Name.ToLower);
      end;
   end;
end;

function RemoveUnicodestr(str: string): string;

   function isChanges(const S: string; var Res: string): Boolean;
   var
      len: Integer;

      function LexemSharp(var K: Integer): Boolean;
      begin
         Result := (K < len) and (S[K] = '#');
         if Result then
         begin
            Inc(K);
            while (K <= len) and (CharInSet(S[K], ['0'..'9'])) do
               Inc(K);
         end;
      end;

      function LexemAp(var K: Integer): Boolean;
      begin
         Result := (K < len) and (S[K] = '''');
         if Result then
         begin
            Inc(K);
            while (K <= len) and (S[K] <> '''') do
               Inc(K);
            if K <= len then
               Inc(K);
         end;
      end;

      function Lexem(var K: Integer; var Str: string): Boolean;
      var
         Start: Integer;
         ValS: string;
      begin
         Result := False;
         Start := K;
         if LexemSharp(K) then
         begin
            ValS := Copy(S, Start + 1, K - Start - 1);
            Str := WideChar(StrToInt(ValS));
            Result := True;
         end
         else if LexemAp(K) then
         begin
            Str := Copy(S, Start + 1, K - Start - 2);
            Result := True;
         end;
      end;

      function Prepare(var K: Integer): string;
      var
         Str: string;
         WasLexem: Boolean;
      begin
         Result := '';
         WasLexem := False;
         while Lexem(K, Str) do
         begin
            Result := Result + Str;
            WasLexem := True;
         end;
         if Result <> '' then
            Result := '''' + Result + '''' + Copy(S, K, Length(S))
         else if not WasLexem then
            Result := S
         else
            Result := '''''';
      end;

      function Min(A, B: Integer): Integer;
      begin
         if A = 0 then
            Result := B
         else if B = 0 then
            Result := A
         else if A > B then
            Result := B
         else
            Result := A;
      end;

   var
      StartIdx: Integer;
   begin
      Result := False;
      StartIdx := Min(Pos('#', S), Pos('''', S));
      if StartIdx > 0 then
      begin
         len := Length(S);
         while (StartIdx <= len) and (not (CharInSet(S[StartIdx], ['#', '''']))) do
            Inc(StartIdx);
         if StartIdx < len then
         begin
            Res := Copy(S, 1, StartIdx - 1) + Prepare(StartIdx);
            Result := True;
         end;
      end;
   end;

var
   Res: string;
begin
   Result := str;
   try
      if isChanges(Result, Res) then
         Result := Res.Trim.DeQuotedString;
      if Pos((' +') + #$D#$A, Result) > 0 then
      begin
         Result := ReplaceStr(Result, Result, '');
      end;
      Result := TrimRight(TrimLeft(Result));
   finally
   end;
end;

{ TDprFile }

constructor TDprFile.Create;
begin
   inherited Create(nil, EmptyStr);
end;

class function TDprFile.IsValidDfm(const AFileName: string): Boolean;
var
   _strStream: TStringStream;
   _content: string;
begin
   _strStream := TStringStream.Create;
   try
      _strStream.LoadFromFile(AFileName);
      _content := _strStream.DataString;
      Result := _content.StartsWith('object', True) or _content.StartsWith('inherited', True) or _content.StartsWith('inline', True);
   finally
      _strStream.Free
   end;
end;

procedure TDprFile.LoadFromFile(const AFileName: string);
begin
   FPath := ExtractFilePath(AFileName);
   Parse(TFile.ReadAllText(AFileName));

end;

procedure TDprFile.LoadFromString(const ADfmContent: string);
begin
   Parse(ADfmContent);
end;

procedure TDprFile.Parse(const ADfmContent: string);
var
   Lines: TStringList;
   LineNumber: Integer;
   LineCount: Integer;
   LineContent: string;
   _startPos, _endPos: Integer;
   _path, _fileName: string;
   dfmFile: TDfmFile;

   function GetLine(ATrim: Boolean = True): string;
   begin
      if ATrim then
      begin
         Result := Lines[LineNumber].Trim;
      end
      else
      begin
         Result := Lines[LineNumber].Trim.TrimRight([#13]);
      end;
      Inc(LineNumber);
   end;

begin
   Lines := TStringList.Create;
   Self.Name := EmptyStr;
   Self.ClassName_ := EmptyStr;
   Self.Id := 0;
   Properties.Clear;
   Objects.Clear;
   Lines.Delimiter := LF;
   Lines.Text := ADfmContent;
   LineCount := Lines.Count;
   LineNumber := 0;
   try
      while LineNumber < LineCount do
      begin

         LineContent := GetLine;
         if Pos(' in ''', LineContent) > 0 then
         begin
            _path := LineContent.TrimRight([',']);
            _startPos := Pos(' in ', LineContent) + 5;
            _endPos := Pos(''' ', LineContent);
            if _endPos = 0 then
               _endPos := Pos(''',', LineContent);
            _path := Copy(_path, _startPos, _endPos - _startPos).DeQuotedString;
            _path := TPath.GetFullPath(TPath.Combine(FPath, _path));
            _fileName := ChangeFileExt(_path, '.dfm');

            if not FileExists(_fileName) then
               Continue;
            if not TDprFile.IsValidDfm(_fileName) then
               Continue;

            dfmFile := TDfmFile.Create;
            dfmFile.LoadFromFile(_fileName);
            Objects.Add(dfmFile);
         end;
         Inc(LineNumber);
      end;
   finally
      FreeAndNil(Lines);
   end;

end;

end.

