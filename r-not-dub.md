**Why use R for compilation rather than Dub?**

There is nothing preventing you from using Dub - I even provide 
[an example](index.html#dub) to show how Dub can be used.

My experience using Dub with embedr has been less than pleasant, while R's
package manager has made things easy. In particular, if I want to call
code inside an R package, it's trivial to do that from within R. R handles
all the necessary linking easily, whereas it's a bit of an adventure to do the
same thing with Dub, in part due to Dub's poor
documentation. To be totally honest, I can't imagine a typical R user 
being able to do much at all with Dub.

tldr: Feel free to use Dub, but the R functions I've written have made
my life a lot easier.

[Index](index.html)
