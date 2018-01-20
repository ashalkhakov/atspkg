import           Language.ATS.Package
import           Test.Hspec

main :: IO ()
main = hspec $
    describe "head" $
        parallel $ it "gets the head of an infinite list" $
            head [1..] `shouldBe` 1
