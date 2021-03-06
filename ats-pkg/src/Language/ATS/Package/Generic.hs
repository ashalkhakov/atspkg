{-# LANGUAGE DerivingStrategies         #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Language.ATS.Package.Generic ( GenericPackage (..)
                                    , InstallDirs (..)
                                    , Package (..)
                                    -- * Functions
                                    , atsInstallDirs
                                    ) where

import           Control.Monad.Reader (ReaderT)
import           Data.Hashable        (Hashable (..))
import           Quaalude

-- | Functions containing installation information about a particular type.
data InstallDirs a = InstallDirs { binDir      :: a -> FilePath
                                 , libDir      :: a -> String -> FilePath
                                 , includeDir  :: a -> FilePath
                                 , includeDeps :: a -> [FilePath]
                                 , libDeps     :: a -> [FilePath]
                                 }

-- | The default set of install dirs for an ATS package.
atsInstallDirs :: Hashable a => IO (InstallDirs a)
atsInstallDirs = do
    h <- getEnv "HOME"
    let binDir' = h ++ "/.local/bin"
        includeDir' = h ++ "/.atspkg/include"
        libDeps' = ["/.atspkg/lib"]
        includeDeps' = ["/.atspkg/include"]
    pure $ InstallDirs (pure binDir') (\pkg n -> "/.atspkg/lib/" ++ n ++ "/" ++ hex (hash pkg)) (pure includeDir') (pure includeDeps') (pure libDeps')

-- | The package monad provides information about the package to be installed,
-- in particular, the directory for installation and the directories for
-- dependencies.
newtype Package a b = Package { unPack :: ReaderT (InstallDirs a) IO b }
    deriving (Functor)
    deriving newtype (Applicative, Monad)

-- | Any type implementing 'GenericPackage' can be depended on by other
-- packages.
class Hashable a => GenericPackage a where

    binRules :: a -> Package a ()
    libRules :: a -> Package a ()
    includeRules :: a -> Package a ()
