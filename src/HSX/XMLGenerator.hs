-----------------------------------------------------------------------------
-- |
-- Module      :  HSX.XMLGenerator
-- Copyright   :  (c) Niklas Broberg 2008
-- License     :  BSD-style (see the file LICENSE.txt)
-- 
-- Maintainer  :  Niklas Broberg, nibro@cs.chalmers.se
-- Stability   :  experimental
-- Portability :  requires newtype deriving and MPTCs with fundeps
--
-- The class and monad transformer that forms the basis of the literal XML
-- syntax translation. Literal tags will be translated into functions of
-- the GenerateXML class, and any instantiating monads with associated XML
-- types can benefit from that syntax.
-----------------------------------------------------------------------------
module HSX.XMLGenerator where

import Control.Monad.Trans
import Control.Monad (liftM)

----------------------------------------------
-- General XML Generation

-- | The monad transformer that allows a monad to generate XML values.
newtype XMLGenT m a = XMLGenT (m a)
  deriving (Monad, Functor, MonadIO)

-- | un-lift.
unXMLGenT :: XMLGenT m a -> m a
unXMLGenT   (XMLGenT ma) =  ma

instance MonadTrans XMLGenT where
 lift = XMLGenT

type Name = (Maybe String, String)

-- | Generate XML values in some XMLGenerator monad.
class Monad m => XMLGen m where
 type XML m
 data Child m
 data Attribute m
 genElement  :: Name -> [XMLGenT m [Attribute m]] -> [XMLGenT m [Child m]] -> XMLGenT m (XML m)
 genEElement :: Name -> [XMLGenT m [Attribute m]]                          -> XMLGenT m (XML m)
 genEElement n ats = genElement n ats []
 xmlToChild :: XML m -> Child m

-- | Type synonyms to avoid writing out the XMLGenT all the time
type GenXML m           = XMLGenT m (XML m)
type GenXMLList m       = XMLGenT m [XML m]
type GenChild m         = XMLGenT m (Child m)
type GenChildList m     = XMLGenT m [Child m]
type GenAttribute m     = XMLGenT m (Attribute m)
type GenAttributeList m = XMLGenT m [Attribute m]

-- | Embed values as child nodes of an XML element. The parent type will be clear
-- from the context so it is not mentioned.
class XMLGen m => EmbedAsChild m c where
 asChild :: c -> GenChildList m

-- | Similarly embed values as attributes of an XML element.
class XMLGen m => EmbedAsAttr m a where
 asAttr :: a -> GenAttributeList m

instance XMLGen m => EmbedAsAttr m (Attribute m) where
 asAttr = return . return

instance EmbedAsAttr m a => EmbedAsAttr m [a] where
 asAttr = liftM concat . mapM asAttr


class (XMLGen m,
       EmbedAsChild m (XML m),
       EmbedAsChild m (Child m),
       EmbedAsChild m (GenXML m),
       EmbedAsChild m (GenXMLList m),
       EmbedAsChild m (GenChild m),
       EmbedAsChild m (GenChildList m),
       SetAttr m (XML m),
       SetAttr m (GenXML m),
       AppendChild m (XML m),
       AppendChild m (GenXML m)
       ) => XMLGenerator m

data Attr n a = n := a
  deriving Show


-------------------------------------
-- Setting attributes

-- | Set attributes on XML elements
class XMLGen m => SetAttr m elem where
 setAttr :: elem -> GenAttribute m     -> GenXML m
 setAll  :: elem -> GenAttributeList m -> GenXML m
 setAttr e a = setAll e $ liftM return a

(<@), set :: (SetAttr m elem, EmbedAsAttr m attr) => elem -> attr -> GenXML m
set xml attr = setAll xml (asAttr attr)
(<@) = set

(<<@) :: (SetAttr m elem, EmbedAsAttr m a) => elem -> [a] -> GenXML m
xml <<@ ats = setAll xml (liftM concat $ mapM asAttr ats)

-------------------------------------
-- Appending children

class XMLGen m => AppendChild m elem where
 appChild :: elem -> GenChild m     -> GenXML m
 appAll   :: elem -> GenChildList m -> GenXML m
 appChild e c = appAll e $ liftM return c

(<:), app :: (AppendChild m elem, EmbedAsChild m c) => elem -> c -> GenXML m
app xml c = appAll xml $ asChild c
(<:) = app

(<<:) :: (AppendChild m elem, EmbedAsChild m c) => elem -> [c] -> GenXML m
xml <<: chs = appAll xml (liftM concat $ mapM asChild chs)

-------------------------------------
-- Names

-- | Names can be simple or qualified with a domain. We want to conveniently
-- use both simple strings or pairs wherever a Name is expected.
class Show n => IsName n where
 toName :: n -> Name

-- | Names can represent names, of course.
instance IsName Name where
 toName = id

-- | Strings can represent names, meaning a simple name with no domain.
instance IsName String where
 toName s = (Nothing, s)

-- | Pairs of strings can represent names, meaning a name qualified with a domain.
instance IsName (String, String) where
 toName (ns, s) = (Just ns, s)


-- literally lifted from the HList library
class TypeCast   a b   | a -> b, b -> a      where typeCast   :: a -> b
class TypeCast'  t a b | t a -> b, t b -> a  where typeCast'  :: t->a->b
class TypeCast'' t a b | t a -> b, t b -> a  where typeCast'' :: t->a->b
instance TypeCast'  () a b => TypeCast a b   where typeCast x = typeCast' () x
instance TypeCast'' t a b => TypeCast' t a b where typeCast' = typeCast''
instance TypeCast'' () a a where typeCast'' _ x  = x
