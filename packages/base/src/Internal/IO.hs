-----------------------------------------------------------------------------
-- |
-- Module      :  Internal.IO
-- Copyright   :  (c) Alberto Ruiz 2010
-- License     :  BSD3
--
-- Maintainer  :  Alberto Ruiz
-- Stability   :  provisional
--
-- Display, formatting and IO functions for numeric 'Vector' and 'Matrix'
--
-----------------------------------------------------------------------------

module Internal.IO (
    dispf, disps, dispcf, vecdisp, latexFormat, format,
    loadMatrix, loadMatrix', saveMatrix
) where

import Internal.Devel
import Internal.Vector
import Internal.Matrix
import Internal.Vectorized
import Text.Printf(printf, PrintfArg, PrintfType)
import Data.List(intersperse,transpose)
import Data.Complex


-- | Formatting tool
table :: String -> [[String]] -> String
table sep as = unlines . map unwords' $ transpose mtp
  where
    mt = transpose as
    longs = map (maximum . map length) mt
    mtp = zipWith (\a b -> map (pad a) b) longs mt
    pad n str = replicate (n - length str) ' ' ++ str
    unwords' = concat . intersperse sep



{- | Creates a string from a matrix given a separator and a function to show each entry. Using
this function the user can easily define any desired display function:

@import Text.Printf(printf)@

@disp = putStr . format \"  \" (printf \"%.2f\")@

-}
format :: (Element t) => String -> (t -> String) -> Matrix t -> String
format sep f m = table sep . map (map f) . toLists $ m

{- | Show a matrix with \"autoscaling\" and a given number of decimal places.

>>> putStr . disps 2 $ 120 * (3><4) [1..]
3x4  E3
 0.12  0.24  0.36  0.48
 0.60  0.72  0.84  0.96
 1.08  1.20  1.32  1.44

-}
disps :: Int -> Matrix Double -> String
disps d x = sdims x ++ "  " ++ formatScaled d x

{- | Show a matrix with a given number of decimal places.

>>> dispf 2 (1/3 + ident 3)
"3x3\n1.33  0.33  0.33\n0.33  1.33  0.33\n0.33  0.33  1.33\n"

>>> putStr . dispf 2 $ (3><4)[1,1.5..]
3x4
1.00  1.50  2.00  2.50
3.00  3.50  4.00  4.50
5.00  5.50  6.00  6.50

>>> putStr . unlines . tail . lines . dispf 2 . asRow $ linspace 10 (0,1)
0.00  0.11  0.22  0.33  0.44  0.56  0.67  0.78  0.89  1.00

-}
dispf :: Int -> Matrix Double -> String
dispf d x = sdims x ++ "\n" ++ formatFixed (if isInt x then 0 else d) x

sdims :: Matrix t -> [Char]
sdims x = show (rows x) ++ "x" ++ show (cols x)

formatFixed :: (Show a, Text.Printf.PrintfArg t, Element t)
            => a -> Matrix t -> String
formatFixed d x = format "  " (printf ("%."++show d++"f")) $ x

isInt :: Matrix Double -> Bool
isInt = all lookslikeInt . toList . flatten

formatScaled :: (Text.Printf.PrintfArg b, RealFrac b, Floating b, Num t, Element b, Show t)
             => t -> Matrix b -> [Char]
formatScaled dec t = "E"++show o++"\n" ++ ss
    where ss = format " " (printf fmt. g) t
          g x | o >= 0    = x/10^(o::Int)
              | otherwise = x*10^(-o)
          o | rows t == 0 || cols t == 0 = 0
            | otherwise = floor $ maximum $ map (logBase 10 . abs) $ toList $ flatten t
          fmt = '%':show (dec+3) ++ '.':show dec ++"f"

{- | Show a vector using a function for showing matrices.

>>> putStr . vecdisp (dispf 2) $ linspace 10 (0,1)
10 |> 0.00  0.11  0.22  0.33  0.44  0.56  0.67  0.78  0.89  1.00

-}
vecdisp :: (Element t) => (Matrix t -> String) -> Vector t -> String
vecdisp f v
    = ((show (dim v) ++ " |> ") ++) . (++"\n")
    . unwords . lines .  tail . dropWhile (not . (`elem` " \n"))
    . f . trans . reshape 1
    $ v

{- | Tool to display matrices with latex syntax.

>>>  latexFormat "bmatrix" (dispf 2 $ ident 2)
"\\begin{bmatrix}\n1  &  0\n\\\\\n0  &  1\n\\end{bmatrix}"

-}
latexFormat :: String -- ^ type of braces: \"matrix\", \"bmatrix\", \"pmatrix\", etc.
            -> String -- ^ Formatted matrix, with elements separated by spaces and newlines
            -> String
latexFormat del tab = "\\begin{"++del++"}\n" ++ f tab ++ "\\end{"++del++"}"
    where f = unlines . intersperse "\\\\" . map unwords . map (intersperse " & " . words) . tail . lines

-- | Pretty print a complex number with at most n decimal digits.
showComplex :: Int -> Complex Double -> String
showComplex d (a:+b)
    | isZero a && isZero b = "0"
    | isZero b = sa
    | isZero a && isOne b = s2++"i"
    | isZero a = sb++"i"
    | isOne b = sa++s3++"i"
    | otherwise = sa++s1++sb++"i"
  where
    sa = shcr d a
    sb = shcr d b
    s1 = if b<0 then "" else "+"
    s2 = if b<0 then "-" else ""
    s3 = if b<0 then "-" else "+"

shcr :: (Show a, Show t1, Text.Printf.PrintfType t, Text.Printf.PrintfArg t1, RealFrac t1)
     => a -> t1 -> t
shcr d a | lookslikeInt a = printf "%.0f" a
         | otherwise      = printf ("%."++show d++"f") a

lookslikeInt :: (Show a, RealFrac a) => a -> Bool
lookslikeInt x = show (round x :: Int) ++".0" == shx || "-0.0" == shx
   where shx = show x

isZero :: Show a => a -> Bool
isZero x = show x `elem` ["0.0","-0.0"]
isOne :: Show a => a -> Bool
isOne  x = show x `elem` ["1.0","-1.0"]

-- | Pretty print a complex matrix with at most n decimal digits.
dispcf :: Int -> Matrix (Complex Double) -> String
dispcf d m = sdims m ++ "\n" ++ format "  " (showComplex d) m

--------------------------------------------------------------------

apparentCols :: FilePath -> IO Int
apparentCols s = f . dropWhile null . map words . lines <$> readFile s
  where
    f [] = 0
    f (x:_) = length x


-- | load a matrix from an ASCII file formatted as a 2D table.
loadMatrix :: FilePath -> IO (Matrix Double)
loadMatrix f = do
    v <- vectorScan f
    c <- apparentCols f
    if (dim v `mod` c /= 0)
      then
        error $ printf "loadMatrix: %d elements and %d columns in file %s"
                       (dim v) c f
      else
        return (reshape c v)

loadMatrix' :: FilePath -> IO (Maybe (Matrix Double))
loadMatrix' name = mbCatch (loadMatrix name)

