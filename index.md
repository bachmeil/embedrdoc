# Overview

One of the limitations of the D programming language is that it doesn't
have the same selection of libraries for data analysis that you have in
a language like R. One way to solve that problem would be to port the many 
thousands of R libraries to D. Doing that would take millions of
programmer hours, and new R libraries appear every day. A more realistic
solution, which I've taken here, is to facilitate communication between
D and R. This can take two forms:

**Calling D functions from R.** The main program is written in R, but 
bottlenecks and anything for which D is better are written in D, 
compiled into a shared library, and loaded into R. This is the procedure
commonly used to call C, C++, and Fortran code from R. 
Other R users can call 
the D functions you've written even if they don't know anything about D.

**Calling R functions from D.** You can use the excellent 
[RInside](https://github.com/eddelbuettel/rinside) project to embed an R 
interpreter inside your D program. Data is passed efficiently because 
everything in R is a C struct (SEXPREC). You can allocate these 
structs from D code and pass pointers to them between the languages. 
This approach is of particular interest to a current R user wanting
to move to D without giving up any of their existing R code and libraries.

# Is This Project Active?

This project is largely complete. Lack of recent activity is a sign that 
the project is stable. I realize that there's a trend to say projects 
are dead if no new features have been added in the last 30 days. If you 
see that the last activity was two years ago, that means it's been 
working so well that I haven't had a reason to make any changes in two 
years. You shouldn't expect to see much activity in an interface between
two mature languages; regularly adding features would be a sign that
something is wrong.

# News

## July 2020

I have three bits of information to share this month:

- At the time of this update, I am unaware of anything that doesn't work.
If something doesn't work, [file an issue](https://bitbucket.org/bachmeil/embedr/issues).
- I plan to move embedr to Github when time allows. Some of the changes 
they've been making to Bitbucket have greatly reduced its usability. The
most notable is that I can only view three lines of code when opening a
source code file on my laptop.
- I want to add more examples and better documentation. If there's
anything unclear or you'd like an example, [file an issue](https://bitbucket.org/bachmeil/embedr/issues).
I'm in the process of updating this file.

## March 2020

Dirk Eddelbuettel merged the changes I made for RInsideC into RInside.
That simplifies installation and usage. It should mean you can embed R
inside a D program on Windows as long as you can get RInside to work on
Windows.

## January 2020

There are two bits of information to share this month:

- I published [a post about embedr on the D blog](https://dlang.org/blog/2020/01/27/d-for-data-science-calling-r-from-d/).
- I've officially given up on native Windows and Docker support. I did 
have both working properly a few years ago. This decision is driven by
three factors:
    - WSL has matured to the point that there's no longer a good reason 
    not to use it.
    - Almost all Windows development now takes place on Windows 10.
    - I don't use Windows and don't have time to dedicate to a
    platform I don't use or understand. To be honest, I'm not aware of 
    even a single Windows user of embedr.
    
    See [this article](https://code.visualstudio.com/docs/remote/wsl) on 
VS Code with WSL. I've tested it and it works well. There's 
no meaningful difference in the editing/compiling/running steps relative
to doing that in Windows natively, except that setup is more complicated
if doing it natively. 

# Documentation

Documentation was produced using [adrdox](https://github.com/adamdruppe/adrdox).
You can view it [here](doc/embedr.html).

# Help

[File an issue](https://bitbucket.org/bachmeil/embedr/issues)
to ask a question if you can't get it to work. I have successfully used
this library on Linux, Mac, and Windows at one time or another, but I 
probably can't help much on Mac or Windows, since I don't have access to
development machines running either of those operating systems.

# Installation

## Linux: Calling D functions from R

1. Install R and the [dmd compiler](http://dlang.org/download.html) 
(obvious, I know, but I just want to be sure). I recommend updating to 
the latest version of R.
2. Install the embedr package using devtools:

```
install_bitbucket("bachmeil/embedr")
```

If you have a standard installation (i.e., as long as you 
haven't done something strange to cause libR.so to be hidden in a place 
the system can't find it) installation is done.

## Linux: Embedding an R interpreter inside a D program

This requires an additional step. After installing embedr as described above, install the RInside package:

```
install.packages("RInside")
```

Note: This functionality was only recently added to RInside. You'll need
to update if you have an older version of RInside installed.

## Windows Installation

See the news item for January 2020. 

An older, previously working Docker
file [can be found here](https://lancebachmeier.com/embedr/dockerusage.html).
That's ancient, so I'm not sure if it will help you.

I'll be happy to let someone else take over Windows support.

## Mac Installation

Mac installation probably works the same as Linux, but since I don't have
a machine to test with, I can't say. I'll be happy to let someone else
take over Mac support.

# Calling D Functions From R: A Simple Example

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

# Calling R From D: A Simple Example

Let's start with an example that tells R print "Hello, World!" to the 
screen. Put the following code in a file named hello.d:

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

This tells dmd to compile your file, handling includes and linking for 
you, and then run it for you. You should see "Hello, World!" printed 
somewhere. The other examples are the same: save the code in a .d file, 
then call the dmd function to compile and run it.

# Dub

I do not normally use Dub. However, many folks do, and if you want to
add dependencies on other libraries like Mir, you don't have much choice
but to use Dub.

Put hello.d in a subdirectory called `src`. In your project's root directory,
i.e., the parent of `src`, put a file called `dub.sdl` with the following
information:

```
name "myproject"
description "embedr hello world"
authors "Lance Bachmeier"
copyright "Copyright 2020, Lance Bachmeier"
license "GPLv2"
versions "standalone"
targetType "executable"
lflags "/usr/lib/libR.so" "/usr/local/lib/R/site-library/RInsideC/lib/libRInside.so"
```

The `lflags` paths may be different on your machine. The first argument
points to libR.so, which depends on where R is installed. The second
argument depends on where the RInsideC package is installed. To find these,
I use this in Bash:

```
locate libR.so -l 1
```

and this in R:

```
paste0(find.package("RInsideC")[1], "/lib/libRInside.so")
```

Alternatively, open R in your project directory and run the following:

```
library(embedr)
dubNew()
```

and it will create a dub.sdl file including the correct paths, create a
src/ directory if it doesn't exist, and add r.d to the src/ directory if
it's not already there.

Drop your source files into the src/ subdirectory, open the terminal in
the project root directory, and compile/run with

```
dub run
```

# Pulling R Data Into D

If you are embedding R inside a D program, and you want to pull data from R into D, please read [this](pulling-r-data.html) first.

# More Examples

The examples above were too basic to be practical. Here are some more
substantial examples.

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

# FAQ

[What's the difference between functions dmd and compileFile?](dmd-vs-compilefile.html)  
[Why use R for compilation rather than Dub?](r-not-dub.html)  
[Can I use LDC?](ldc.html)  

