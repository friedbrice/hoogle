
module Hoogle.TypeSig.Type where

import Data.Binary.Defer
import Data.List
import Data.Generics.UniplateOn


---------------------------------------------------------------------
-- DATA TYPES

data TypeSig = TypeSig Constraint Type
               deriving (Eq,Ord)

type Constraint = [Type]

-- TODO: Add TForAll and treat it properly throughout
--       Add TBang to handle bangs properly
data Type = TApp Type [Type] -- a list of types, first one being the constructor
          | TLit String -- bound variables, Maybe, ":", "(,)", "(,,)" (tuple)
          | TVar String -- unbound variables, "a"
          | TFun [Type]
          deriving (Eq,Ord)


tApp :: Type -> [Type] -> Type
tApp t [] = t
tApp t ts = TApp t ts


fromTFun :: Type -> [Type]
fromTFun (TFun x) = x
fromTFun x = [x]


fromTApp :: Type -> (Type, [Type])
fromTApp (TApp x y) = (x,y)
fromTApp x = (x,[])


isTLitTuple :: String -> Bool
isTLitTuple x = ',' `elem` x


insertTApp, removeTApp :: Type -> Type
insertTApp = transform f
    where
        f (TApp (TApp x []) y) = TApp x y
        f (TApp x y) = TApp x y
        f (TFun x) = TFun x
        f x = TApp x []

removeTApp = transform f
    where
        f (TApp x []) = x
        f x = x


---------------------------------------------------------------------
-- UNIPLATE INSTANCES

onTypeSig :: BiplateType TypeSig Type
onTypeSig (TypeSig xs x) = (x:xs, \(x:xs) -> TypeSig xs x)

instance Uniplate Type where
    uniplate (TApp x xs) = (x:xs, \(x:xs) -> TApp x xs)
    uniplate (TFun xs) = (xs, \xs -> TFun xs)
    uniplate x = ([], \[] -> x)


---------------------------------------------------------------------
-- BINARYDEFER INSTANCES

instance BinaryDefer TypeSig where
    put (TypeSig a b) = put2 a b
    get = get2 TypeSig

instance BinaryDefer Type where
    put (TApp a b) = putByte 0 >> put2 a b
    put (TLit a)   = putByte 1 >> put1 a
    put (TVar a)   = putByte 2 >> put1 a
    put (TFun a)   = putByte 3 >> put1 a

    get = do
        i <- getByte
        case i of
            0 -> get2 TApp
            1 -> get1 TLit
            2 -> get1 TVar
            3 -> get1 TFun


---------------------------------------------------------------------
-- SHOW INSTANCES

showConstraint :: Constraint -> String
showConstraint [] = ""
showConstraint [x] = show x ++ " => "
showConstraint xs = "(" ++ concat (intersperse ", " $ map show xs) ++ ") => "


instance Show Type where
    showsPrec i x = showString $ f i x
        where
            f i (TApp (TLit "[]") [x]) = "[" ++ show x ++ "]"
            f i (TApp (TLit ('(':tup)) xs)
                | not (null tup) && last tup == ')' && all (== ',') (init tup) && length tup == length xs
                = b True $ concat $ intersperse ", " $ map show xs
            
            f i (TLit x) = x
            f i (TVar x) = x
            
            f i (TApp x xs) = b (i > 1) $ concat (intersperse " " $ map (f 2) (x:xs))
            f i (TFun xs)   = b (i > 0) $ concat (intersperse " -> " $ map (f 1) xs)
            
            b True x = "(" ++ x ++ ")"
            b False x = x


instance Show TypeSig where
    show (TypeSig x xs) = showConstraint x ++ show xs


-- shows an element within a function
-- to get brackets right after splitFun
showFun :: Type -> String
showFun x = showsPrec 1 x ""


---------------------------------------------------------------------
-- OPERATIONS

normaliseTypeSig :: TypeSig -> TypeSig
normaliseTypeSig = transformOn onTypeSig f
    where
        f (TApp x []) = x
        f (TApp (TLit "->") xs) = f $ TFun xs
        f (TFun [x]) = x
        f (TFun xs) = TFun $ g xs
        f x = x

        g [] = []
        g [TFun xs] = g xs
        g (x:xs) = x : g xs


splitFun :: Type -> [Type]
splitFun (TFun xs) = xs
splitFun x = [x]


renameVars :: (String -> String) -> TypeSig -> TypeSig
renameVars f = transformOn onTypeSig g
    where
        g (TVar x) = TVar $ f x
        g x = x
