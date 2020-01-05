# Overview

D is a nice programming language, but it doesn't have many libraries for 
statistical analysis. One way to solve that problem would be to port all 
of R's libraries to D. With a million programmer hours, you could 
get a good start on that task. A more realistic solution, taken here, is 
to facilitate communication between D and R. This can be done in two ways:

**Calling D functions from R.** The main program is written in R, but 
bottlenecks and anything for which D is better are written in D, 
compiled into a shared library, and loaded into R. 
This procedure is commonly used to call C, C++, and Fortran code from R. 
The primary advantage of this approach is that other R users can call 
the D functions you've written, even if they don't know anything about 
D. Currently, this can be done using DMD or LDC on Linux, and LDC on
Mac.

**Calling R functions from D.** You can use the excellent 
[RInside](https://github.com/eddelbuettel/rinside) project to embed an R 
interpreter inside your D program. Data is passed efficiently because 
everything in R is a C struct (SEXPREC). You can allocate SEXPREC 
structs from D code and pass pointers to them between the languages. 
This approach is best for someone that prefers to write as much as
possible in D without giving up any functionality they have in R.

# Is This Project Active?

This project is largely complete. Lack of recent activity is a sign that 
the project is stable. I realize that there's a trend to say projects 
are dead if no new features have been added in the last 30 days. If you 
see that the last activity was two years ago, that means it's been 
working so well that I haven't had a reason to make any changes in two 
years. You shouldn't expect to see much activity in an interface between
two mature languages; regularly adding features would be a sign that
something is wrong.

As of this update (Jan 04, 2020) I am unaware of anything that doesn't work. If something doesn't work, [file an issue](https://bitbucket.org/bachmeil/embedr/issues). 

# Documentation

Documentation was produced using [adrdox](https://github.com/adamdruppe/adrdox).
You can view it [here](doc/embedr.html).

# Calling D Functions From R

I have successfully done this on Linux, Mac, and Windows. Linux support
is best because that's the OS I use. [File an issue](https://bitbucket.org/bachmeil/embedr/issues)
to ask a question if you can't get it to work.

## Linux Installation

If you only want to call D functions from R, installation is easy.

1\. Install R and the [dmd compiler](http://dlang.org/download.html) 
(obvious, I know, but I just want to be sure). I recommend updating to 
the latest version of R.
2\. Install the embedr package using devtools:

```
install_bitbucket("bachmeil/embedr")
```

That is it. If you have a standard installation (i.e., as long as you 
haven't done something strange to cause libR.so to be hidden in a place 
the system can't find it) you are done.

## Windows Installation

*Update (Jan 04, 2020):* I've decided to officially abandon Windows support. The main reason for this is the fact that Microsoft's WSL works so well, and is so convenient to use, that you should be using it if at all possible. See [this article](https://code.visualstudio.com/docs/remote/wsl) for using VS Code with WSL. I've used that approach and it's a very reasonable choice - there's essentially no difference in the editing/compiling/running steps, with the exception that the Windows approach is messier. 

Windows 10 has now been out for five years. Windows 7 is losing Microsoft's support soon, and Windows 8 is not heavily used. I doubt there is even one Windows 7 or 8 user of embedr.

I'm happy to accept pull requests if someone wants to take over Windows support. Furthermore, you might try [Docker](https://lancebachmeier.com/embedr/dockerusage.html).

## Mac Installation

Installation on Mac is similar to Linux, but as I do not have access to
a Mac, it is hard for me to add that functionality to embedr.
That is the only reason embedr does not currently support Mac. 
[Docker](https://lancebachmeier.com/embedr/dockerusage.html) works well.
Please contact me if you are a Mac user and would like to take over
embedr's Mac support. [File an issue](https://bitbucket.org/bachmeil/embedr/issues)
if you have questions about getting it to work. I'll gladly add Mac support if someone sends me a recent model Macbook or the money to buy one. (Just to be clear, I don't actually expect anyone to do that, but that's what it will take.)

# Embedding R Inside D

This should work without problems on Linux, Windows, or Mac, but I've
only been able to test it on Linux. The easy approach is to do the
compilation with the embedr package. Alternatively, you can use Dub, and
I provide an example dub.sdl file below.

Currently I can only give documentation for Linux because that is all I
have used. There is no reason that it won't work on Windows or Mac,
especially if you use Dub. If you use one of those platforms and you are
interested in adding official support to embedr, please contact me.

## Linux Installation

Embedding R inside D requires you to install a slightly modified version 
of the RInside package in addition to everything above.

1\. Install R and the [dmd compiler](http://dlang.org/download.html) 
(obvious, I know, but I just want to be sure). I recommend updating to 
the latest version of R.  
2\. Install [RInsideC](https://bitbucket.org/bachmeil/rinsidec) using 
devtools. In R:
    
```
library(devtools)
install_bitbucket("bachmeil/rinsidec")
```
    
3\. Install the embedr package using devtools:

```
install_bitbucket("bachmeil/embedr")
```

That is it. If you have a standard installation (i.e., as long as you 
haven't done something strange to cause libR.so to be hidden in a place 
the system can't find it) you are done.

# Example: Calling D Functions From R

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

# Example: Calling R Functions From D

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

If you are familiar with Dub and want to create a package for code.dlang.org, please do. You don't need my permission.

# Pulling R Data Into D

If you are embedding R inside a D program, and you want to pull data from R into D, please read [this](pulling-r-data.html) first.

# More Examples

The examples above were too basic to be practical. Here are some examples
that demonstrate more useful functionality.

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

