{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell   #-}

-- | This module contains functions for installing the @patscc@ compiler. It
-- also includes functions for building @libatslib@.
module Language.ATS.Package.Compiler
    ( packageCompiler
    , fetchCompiler
    , setupCompiler
    , cleanAll
    -- * Types
    , SetupScript
    ) where

import qualified Codec.Archive.Tar       as Tar
import           Codec.Compression.GZip  (compress, decompress)
import           Control.Composition
import           Control.Monad
import qualified Data.ByteString.Lazy    as BS
import           Data.Dependency
import           Data.FileEmbed
import           Network.HTTP.Client     hiding (decompress)
import           Network.HTTP.Client.TLS (tlsManagerSettings)
import           Quaalude
import           System.Environment      (getEnv)
import           System.FilePath.Find    (find)
import           System.Process.Ext      (silentCreateProcess)

libatsCfg :: String
libatsCfg = $(embedStringFile "dhall/atslib.dhall")

compilerDir :: Version -> IO FilePath
compilerDir v = makeAbsolute =<< dir
    where dir = (++ ("/.atspkg/" ++ show v)) <$> getEnv "HOME"

-- | Make a tarball from a directory containing the compiler.
packageCompiler :: FilePath -> IO ()
packageCompiler directory = do
    files <- find (pure True) (pure True) directory
    bytes <- fmap Tar.write . Tar.pack directory $ fmap (drop $ length (directory :: String) + 1) files
    BS.writeFile (directory ++ ".tar.gz") (compress bytes)

pkgUrl :: Version -> String
pkgUrl v = "https://github.com/vmchale/atspkg/releases/download/compiler/ATS2-Postiats-" ++ show v ++ ".tar.gz"

withCompiler :: String -> Version -> IO ()
withCompiler s v = putStrLn $ s ++ " compiler v" ++ show v ++ "..."

fetchCompiler :: Version -> IO ()
fetchCompiler v = do

    cd <- compilerDir v
    needsSetup <- not <$> doesDirectoryExist cd

    when needsSetup $ do

        withCompiler "Fetching" v
        manager <- newManager tlsManagerSettings
        initialRequest <- parseRequest $ pkgUrl v
        response <- responseBody <$> httpLbs (initialRequest { method = "GET" }) manager

        withCompiler "Unpacking" v
        Tar.unpack cd . Tar.read . decompress $ response

make :: Version -> FilePath -> IO ()
make v cd =
    withCompiler "Building" v >>
    silentCreateProcess ((proc "make" []) { cwd = Just cd })

type SetupScript = Maybe String -- ^ Optional target triple
                     -> String -- ^ Library name
                     -> FilePath -- ^ File path
                     -> IO ()

libInstall :: SetupScript -> FilePath -> String -> IO ()
libInstall atslibSetup cd triple =
    unless (triple == "musl") $ mconcat
        [ putStrLn "Installing cross libraries..."
        , writeFile (cd ++ "/atspkg.dhall") libatsCfg
        , atslibSetup (Just triple) "atslib" cd
        ]

install :: Maybe String
        -> SetupScript
        -> Version
        -> FilePath
        -> IO ()
install tgt' als v cd =
    withCompiler "Installing" v >>
    silentCreateProcess ((proc "make" ["install"]) { cwd = Just cd }) >>
    maybe mempty (libInstall als cd) tgt'

configure :: FilePath -> Version -> FilePath -> IO ()
configure configurePath v cd = do

    withCompiler "Configuring" v

    setFileMode configurePath ownerModes
    setFileMode (cd ++ "/autogen.sh") ownerModes

    silentCreateProcess ((proc (cd ++ "/autogen.sh") []) { cwd = Just cd })

    silentCreateProcess ((proc configurePath ["--prefix", cd]) { cwd = Just cd })

setupCompiler :: SetupScript -> Maybe FilePath -> Version -> IO ()
setupCompiler als tgt' v = do

    cd <- compilerDir v

    biaxe [configure (cd ++ "/configure"), make, install tgt' als] v cd

    writeFile (cd ++ "/done") ""

cleanAll :: IO ()
cleanAll = do
    d <- (++ "/.atspkg") <$> getEnv "HOME"
    b <- doesDirectoryExist d
    when b $ do
        putStrLn "Cleaning everything..."
        removeDirectoryRecursive d
