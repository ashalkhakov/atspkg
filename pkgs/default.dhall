let pkg
  = { bin = []
      : List { src : Text, target : Text, libs : List Text, hsDeps : List { cabalFile : Text, objectFile : Text } , hs2ats : List { hs : Text, ats : Text }, gc : Bool }
    , test = []
      : List { src : Text, target : Text, libs : List Text, hsDeps : List { cabalFile : Text, objectFile : Text } , hs2ats : List { hs : Text, ats : Text }, gc : Bool }
    , man = ([] : Optional Text)
    , version = [0,3,9]
    , compiler = [0,3,9]
    , dependencies = []
      : List { libName : Text, dir : Text, url : Text, libVersion : List Integer }
    , clib = []
      : List { libName : Text, dir : Text, url : Text, libVersion : List Integer }
    , ccompiler = "gcc"
    , cflags = [ "-O2", "-flto" ]
    , atsSource = ([] : List Text)
    , cDir = "cbits"
    }

in pkg
