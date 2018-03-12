# embedr

D is a nice programming language, but it doesn't have many libraries for 
statistical analysis. One way to solve that problem would be to port all 
of R's libraries to D. With a few million programmer hours, you could 
get a good start on that task. A more realistic solution, taken by this 
project, is to facilitate communication between D and R. This can be 
done in two ways:

**Calling D functions from R.** The main program is written in R, but 
bottlenecks and anything for which D is better are rewritten in D, 
compiled into a shared library, and loaded into R. 
This procedure is commonly used to call C, C++, and Fortran code from R. 
The primary advantage of this approach is that other R users can call 
the D functions you've written, even if they don't know anything about 
D. Currently, this can be done using DMD or LDC on Linux, and LDC on
Windows or Mac.

**Calling R functions from D.** You can use the excellent 
[RInside](https://github.com/eddelbuettel/rinside) project to embed an R 
interpreter inside your D program. Data is passed efficiently because 
everything in R is a C struct (SEXPREC). You can allocate SEXPREC 
structs from D code and pass pointers to them between the languages. 
This approach is best for someone that prefers to write as much as
possible in D without giving up any functionality they have in R.
This should work without problems on Linux, Windows, or Mac, but I've
only tested it on Linux. There is a dub.sdl file below if you want to
try it out. Docker works well on Windows and Mac. You can find a 
Dockerfile and an explanation of how to use it 
[here](https://lancebachmeier.com/embedr/dockerusage.html). If you are
using Windows 10, the combination of WSL with ConEmu works very well.

## Library Documentation

Documentation was produced using [adrdox](https://github.com/adamdruppe/adrdox).
You can view it [here](doc/embedr.html).

## Linux Installation (calling D functions from R)

If you only want to call D functions from R, installation is easy.

1\. Install R and the [dmd compiler](http://dlang.org/download.html) (obvious, I know, but I just want to be sure). I recommend updating to the latest version of R.
2\. Install the embedr package using devtools:

```
install_bitbucket("bachmeil/embedr")
```

That is it. If you have a standard installation (i.e., as long as you haven't done something strange to cause libR.so to be hidden in a place the system can't find it) you are done.

## Linux Installation (calling R functions from D)

Embedding R inside D requires you to install a slightly modified version of the RInside package in addition to everything above.

1\. Install R and the [dmd compiler](http://dlang.org/download.html) (obvious, I know, but I just want to be sure). I recommend updating to the latest version of R.  
2\. Install [RInsideC](https://bitbucket.org/bachmeil/rinsidec) using devtools. In R:
    
```
library(devtools)
install_bitbucket("bachmeil/rinsidec")
```
    
3\. Install the embedr package using devtools:

```
install_bitbucket("bachmeil/embedr")
```

That is it. If you have a standard installation (i.e., as long as you haven't done something strange to cause libR.so to be hidden in a place the system can't find it) you are done.

## Windows Installation (calling D functions from R)

This is a little trickier for a variety of reasons. The only recommended
approach at this time is to let the embedr package install the LDC
compiler and do the configuration for you.

1\. Install R. I recommend updating to the latest version of R.  
2\. Install the embedr package using devtools:

```
library(devtools)
install_bitbucket("bachmeil/embedr")
```
    
3\. Install the LDC compiler and configure everything:

```
library(embedr)
ldc.install()
embedr.configure()
```

You should be done at this point. I cannot guarantee that, however, due
to problems with directories being changed by Windows to read-only status.
More details can be found [here](https://lancebachmeier.com/computing/d-from-r-windows.html).

## Examples: Calling D Functions From R

Note that Windows requires an explicit export attribute when defining a
function that is to be included as part of a shared library. I present
both versions of the simple example to clarify that, but for the other examples
you will have to add the export attribute. There are some other differences
in the Linux and Windows versions. These are due to the fact that those
functions were created at different times, and I have not yet had time
to make things consistent. I will eventually get around to doing that.

## Simple Example (Linux)

Save this code in a file called librtest.d:

```
extern(C) {
  Robj add(Robj rx, Robj ry) {
    double result = rx.scalar + ry.scalar;
    return result.robj;
  }
}
```

Then in R, from the same directory as librtest.d, create and load the
shared library using the `dmd` function:

```
compileFile("librtest.d", "rtest")
```

Test it out:

```
.Call("add", 2.5, 3.65)
```

## Simple Example (Windows)

The same thing can be achieved in Windows as follows. Save this code in
librtest.d:

```
import embedr.r;
mixin(createRLibrary("rtest"));

export extern(C) {
  Robj add(Robj rx, Robj ry) {
    double result = rx.scalar + ry.scalar;
    return result.robj;
  }
}
```

In the same directory as librtest.d, create and load the DLL:

```
ldc("librtest")
```

Test it out:

```
.Call("add", 2.5, 3.65)
```

## Embedding R Inside D

The examples that follow work on Linux.

## Hello World

Let's start with an example that has R print "Hello, World!" to the screen. Put the following code in a file named hello.d:

```
import embedr.r;

void main() {
	evalRQ(`print("Hello, World!")`);
}
```

In the directory containing hello.d, run the following in R:

```
library(embedr)
dmd("hello")
```

This will tell dmd to compile your file, handling includes and linking for you, and then run it for you. You should see "Hello, World!" printed somewhere. The other examples are the same: save the code in a .d file, then call the dmd function to compile and run it.

## Using Dub

I do not normally use Dub. However, many folks do, and if you want to
add dependencies on other libraries like Mir, you don't have much choice
but to use Dub.

Here's the dub.sdl file I used to compile the Hello World example above:

```
name "myproject"
description "embedr hello world"
authors "lance"
copyright "Copyright 2018, lance"
license "GPLv2"
versions "r" "standalone"
lflags "/usr/lib/libR.so" "/usr/local/lib/R/site-library/RInsideC/lib/libRInside.so"
```

The `lflags` paths may be different on your machine, and they definitely
will be different if you're not using Linux.

## Passing a Matrix From D to R

Let's write a program that tells R to allocate a (2x2) matrix, fills the elements in D, and prints it out in both D and R.

```
import embedr.r;

void main() {
	auto m = RMatrix(2,2);
	m[0,0] = 1.5;
	m[0,1] = 2.5;
	m[1,0] = 3.5;
	m[1,1] = 4.5;
	m.print("Matrix allocated by R, but filled in D");
}
```

`RMatrix` is a struct that holds a pointer to an R object plus the dimensions of the matrix. When the constructor is called with two integer arguments, it has R allocate a matrix with those dimensions.

The library includes some basic functionality for working with `m`, including getting and setting elements, and printing. Alternatively, we could have passed `m` to R and told R to print it:

```
import embedr.r;

void main() {
	auto m = RMatrix(2,2);
	m[0,0] = 1.5;
	m[0,1] = 2.5;
	m[1,0] = 3.5;
	m[1,1] = 4.5;
  m.toR("mm"); // Now there is an object inside R called mm
  evalRQ(`print(mm)`);
```

## Passing a Matrix From R to D

We can also pass a matrix in the opposite direction. Let's allocate and fill a matrix in R and then work with it in D.

```
import embedr.r;

void main() {
  // Generate a (20x5) random matrix in R
  evalRQ(`m <- matrix(rnorm(100), ncol=5)`);
  
  // Create an RMatrix struct in D that holds a pointer to m
  auto dm = RMatrix("m");
  dm.print("This is a matrix that was created in R");
  
  // Change one element and verify that it has changed in R
  dm[0,0] = dm[0,0]*4.5;
  printR("m");
}
```

A comment on the last line: `printR` uses the R API printing function to print an R object. If you pass a string as the argument to `printR`, it will print the object with that name in R. It will *not* print the string that you pass to it as an argument. D does not know anything about `m`. It only knows about `dm`, which holds a pointer to `m`.

## RVector

A vector can be represented as a matrix with one column. In R, vectors and matrices are entirely different objects. That doesn't matter much in D because vectors *are* represented as matrices in D. I have added an `RVector` struct to allow the use of `foreach`. Here is an example:

```
import embedr.r;
import std.stdio;

void main() {
  // Have R allocate a vector with 5 elements and copy the elements of the double[] into it
	auto v = RVector([1.1, 2.2, 3.3, 4.4, 5.5]);
  
  // Pass v to R, creating variable rv inside the R interpreter
	v.toR("rv");
	printR("rv");
	
  // Use foreach to print the elements
	foreach(val; v) {
		writeln(val);
	}
}
```

## RVector Slices

You can slice an RVector, as shown in this example.

```
import embedr.r;
import std.stdio;

void main() {
	evalRQ(`v <- rnorm(15)`);
	auto rv = RVector("v");
	foreach(val; rv) {
		writeln(val);
	}
	rv[1..5].print("This is a slice of the vector");
}
```

## Working With R Lists

Lists are very important in R, as they are the most common way to construct a heterogeneous vector. Although you could work directly with an R list (there's an `RList` struct to do that) you lose most of the nice features if you do. For that reason I created the `NamedList` struct. You can refer to elements by number (elements are ordered as in any array) or by name. You can add elements by name (but only that way, because every element in a `NamedList` needs a name).

```

import embedr.r;
import std.stdio;

void main() {
  // Create a list in R
  evalRQ(`rl <- list(a=rnorm(15), b=matrix(rnorm(100), ncol=4))`);
  
  // Create a NamedList struct to work with it in D
  auto dl = NamedList("rl");
  dl.print;
  
  // Pull out a matrix
  auto dlm = RMatrix(dl["b"]);
  dlm.print("This is the matrix from that list");
  
  // Pull out a vector
  auto dlv = RVector(dl["a"]);
  dlv.print("This is the vector from that list");

  // Create a NamedList in D and put some R objects into it
  // NamedList holds pointers to R objects, which can be pulled
  // out using .data
  NamedList nl;
  nl["a"] = dlm.data;
  nl["b"] = dlv.data;
  
  // Send to R as rl2
  nl.toR("rl2");
	
  // Can verify that the elements are reversed
  printR("rl2");
}
```

## Scalars and Strings

R does not have a scalar type. What appears to be a scalar is a vector with one element. On the D side, however, there are scalars, so you have to specify that you are working with a scalar your D code. On a different note, we can pass strings between R and D.

```
import embedr.r;
import std.stdio;

void main() {
  // Create some "scalars" in R
  evalRQ(`a <- 4L`);
  evalRQ(`b <- 4.5`);
  evalRQ(`d <- "hello world"`);
	
  // Print the values of those R variables from D
  // Pull the integer a from R into D
  writeln(scalar!int("a"));
  
  // Also pulls in an integer, but creates a long rather than int
  writeln(scalar!long("a"));
  
  // The default type of scalar is double, so it is not necessary to specify the type in that case
  writeln(scalar("b"));
  
  // Pull the string d from R into D
  writeln(scalar!string("d"));
	
  // Can also work with a string[]
  ["foo", "bar", "baz"].toR("dstring");
  printR("dstring");
	
  // Create a vector of strings in R and pull it into D as a string[]
  evalRQ(`rstring <- c("under", "the", "bridge")`);
  writeln(stringArray("rstring"));
}
```

There is more functionality available (the entire R API, in fact) but the single goal of this library is to facilitate the passing of commonly-used data types between the two languages. Other libraries are available for the functions in the R standalone math library, optimization, and so on.
