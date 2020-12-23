{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit amw_ide_tools;

{$warn 5023 off : no warning about unused units}
interface

uses
  amw_ide_menu_items, AndroidGdb, AndroidProjOptions, ApkBuild, 
  lamwtoolsoptions, uFormBuildFPCCross, uFormComplements, uFormGetFPCSource, 
  uformimportjarstuff, uformimportlamwstuff, uformsettingspaths, 
  uFormStartEmulator, ufrmCompCreate, ufrmEditor, uimportcstuff, 
  uimportjavastuff, uimportjavastuffchecked, unitformimportpicture, 
  uregistercompform, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('amw_ide_menu_items', @amw_ide_menu_items.Register);
  RegisterUnit('AndroidGdb', @AndroidGdb.Register);
end;

initialization
  RegisterPackage('amw_ide_tools', @Register);
end.
