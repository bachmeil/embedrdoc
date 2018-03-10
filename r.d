/**
 * This module provides an interface to the R API. It allows you to
 * write D functions that can be called from R and also provides support
 * for embedding an R interpreter inside a D program. That means you have
 * access to all R libraries from within a D program. Data is passed
 * between the two languages using pointers. This modules defines
 * structs that handle protecting/unprotecting data from the R garbage
 * collector.
 * 
 * This file contains everything you need to create a shared library on
 * Linux or Mac that can be called from R. On Windows, you will also need
 * the R.lib file provided inside the repo.
 * 
 * License: [Boost License 1.0](http://boost.org/LICENSE_1_0.txt)
 * 
 * Author: Lance Bachmeier
 */
module embedr.r;

import std.algorithm, std.array, std.conv, std.math, std.range, std.stdio, std.string, std.utf;

version(gretl) {
  import gretl.matrix;
}
version(standalone) {
  import std.exception;
}
version(inline) {
  private alias enforce = embedr.r.assertR;
}

/**
 * All data in R is stored in an opaque struct called `sexprec`. Data is
 * passed around as pointers to `sexprec` structs called `SEXP`. That's
 * an unfortunate name (it stands for s-expression because R started out
 * as a Scheme dialect) so I use `Robj` instead.
 */
struct sexprec {}

/** ditto */
alias Robj = sexprec*; 

/**
 * Enables reference counting of objects allocated by R. It takes
 * care of protecting and unprotecting objects from the R garbage
 * collector. 
 * 
 * R objects allocated inside R and passed to D are automatically
 * protected. Attempting to protect/unprotect them will result in an error.
 * R objects allocated by D have to be protected from the garbage collector
 * while they are active, and unprotected when you are done with them.
 * 
 * This is an implementation of the reference counting scheme in Adam
 * Ruppe's $(I D Cookbook).
 * 
 * $(WARNING This does not do anything to protect an R object. `ProtectedRObject`
 * holds an object that has already been protected and unprotects it when
 * there are no more references to it.)
 */
private struct RObjectStorage {
  Robj ptr; /// The `Robj` struct to be protected
  /** A flag indicating that the object needs to be unprotected
 * when there are no more references to it. Set to `false` if working with
 * data that was allocated in R and passed to D.*/
  bool unprotect;
  int refcount; /// The number of active references to `ptr`.
}

/// ditto
struct ProtectedRObject {
  RObjectStorage * data; /// Wrapper around the data that holds the reference count
  alias data this; ///
	
  /** Params:
   * x = R object that you want to protect
   * u = Flag indicating that the object needs to be unprotected. This is
   * `false` if you are making a copy of the struct, or if you are holding
   * an object that was allocated inside R and passed to D.
   */
  this(Robj x, bool u=false) {
    data = new RObjectStorage();
    data.ptr = x;
    data.refcount = 1;
    data.unprotect = u;
  }
	
	/// Needed to change the reference count.
  this(this) {
    if (data.unprotect) {
      enforce(data !is null, "data should never be null inside an ProtectedRObject. You must have created an ProtectedRObject without using the constructor.");
      data.refcount += 1;
    }
  }
	
	/** Unprotects the `Robj` if the reference count hits zero
	 *  and `unprotect` is `true`. 
	 */
  ~this() {
    if (data.unprotect) {
      enforce(data !is null, "Calling the destructor on an ProtectedRObject when data is null. You must have created an ProtectedRObject without using the constructor.");
      data.refcount -= 1;
      if (data.refcount == 0) {
	Rf_unprotect_ptr(data.ptr);
      }
    }
  }
	
	/** For convenience, returns the underlying `Robj` when you want to
	 *  pass the data back to R.
	 */
  Robj robj() {
    return data.ptr;
  }
}

version(standalone) {
  extern (C) {
    void passToR(Robj x, char * name);
    Robj evalInR(char * cmd);
    void evalQuietlyInR(char * cmd);
  }

	/**
	 * When embedding an R interpreter inside D, this function passes
	 * data from D to R, copying as necessary.
	 */
  void toR(T)(T x, string name) {
    passToR(x.robj, toUTFz!(char*)(name));
  }

	/// ditto
  void toR(Robj x, string name) {
    passToR(x, toUTFz!(char*)(name));
  }

	/// ditto
  void toR(string[] s, string name) {
    passToR(s.robj, toUTFz!(char*)(name));
  }

	/** For embedding an R interpreter inside D.
	 * 
	 * Params:
	 * 	cmd = String of R code that is passed to R and evaluated.
	 * 
	 * Returns: An `Robj` holding the result of the evaluation of `cmd`.
	 * 	If nothing is returned, as for instance when you evaluate `y <- 3+2`,
	 *  the return value will be an `Robj` struct holding `RNil`.
	 * 
	 * See_Also: [evalRQ]
	 */
  Robj evalR(string cmd) {
    return evalInR(toUTFz!(char*)(cmd));
  }

	/** For embedding an R interpreter inside D.
	 * 
	 * Params:
	 * 	cmd = String of R code that is passed to R and evaluated.
	 * 
	 * See_Also: [evalR]
	 */
  void evalRQ(string cmd) {
    evalQuietlyInR(toUTFz!(char*)(cmd));
  }

	/** For embedding an R interpreter inside D.
	 * 
	 * Params:
	 * 	cmds = String array of R code that is passed to R and evaluated one
	 *  element at a time.
	 * 
	 * See_Also: [evalR]
	 */
  void evalRQ(string[] cmds) {
    foreach(cmd; cmds) {
      evalQuietlyInR(toUTFz!(char*)(cmd));
    }
  }
}

/** For use inside D functions called from R.
 * 
 * Calls into the R API function `Rf_error` to throw an error if a test condition is not
 * met. Used to stop the R program from running when there is an error in the D
 * code. Without using `assertR`, there will normally be a segmentation
 * fault and little information about the error. Those are nasty, so you
 * want to add calls to `assertR` all over your code.
 * 
 * $(TIP `assertR` is aliased to `enforce`, so you can use `enforce` everywhere
 * (D code calling R or R code calling D functions) if you want.)
 * 
 * Params:
 * 	test = A test for code correctness.
 * 	msg = The error message to return from R if `test` is `false`.
 * 
 * Examples:
 * 
 * ---
 * // Obviously have mixed up the high and low temperatures
 * int low = 75;
 * int high = 42;
 * assertR(high >= low, "Cannot have the day's high temperature 
 * be less than the day's low temperature");
 * ---
 * 
 * ---
 * double[] x = [3.1, 4.7, 1.8];
 * int ii = 3;
 * double z = x[ii]; // out of bounds error, will cause a segmentation fault
 * assertR(ii < x.length, "Index greater than the number of elements");
 * ---
 */
void assertR(bool test, string msg) {
  if (!test) {
    Rf_error( toUTFz!(char*)("Error in D code: " ~ msg) );
  }
}

/** Tells the R interpreter to print something out. This is generally useful
 *  only if you want to use the formatting provided by R. Most of the time,
 *  want to do your printing from D.
 */ 
void printR(Robj x) {
  Rf_PrintValue(x);
}

/// Ditto
void printR(ProtectedRObject x) {
  Rf_PrintValue(x.robj);
}

version(standalone) {
	/// Ditto
  void printR(string s) {
    evalRQ(`print(` ~ s ~ `)`);
  }

	/** Tells R to source the file `s`.
	 */
  void source(string s) {
    evalRQ(`source("` ~ s ~ `")`);
  }
}

/** All R objects have a length attribute. You can call this function
 *  on any R object and it will return a value. The most common usage
 *  is to get the length of a vector, but it can be called on anything.
 */
int length(Robj x) {
  return Rf_length(x);
}

/** Returns `true` if `x` is a vector object.
 * 
 * Will return `true` if `x` is a vector or list, but `false` if `x` is
 * a matrix.
 * 
 * $(WARNING R does not have a scalar type. "Scalars" in R are vectors with
 * one element, so this function cannot be used to distinguish between
 * vectors and scalars.)
 */
bool isVector(Robj x) {
  return to!bool(Rf_isVector(x));
}

/** Returns `true` if `x` holds a matrix.
 */
bool isMatrix(Robj x) {
  return to!bool(Rf_isMatrix(x));
}

/** Returns `true` if `x` holds a vector of integers or doubles.
 * 
 * $(WARNING R does not have a scalar type. "Scalars" in R are vectors with
 * one element, so this function cannot be used to distinguish between
 * vectors and scalars.)
 */
bool isNumeric(Robj x) {
  return to!bool(Rf_isNumeric(x));
}

/** Returns `true` if `x` holds a vector of integers.
 * 
 * $(WARNING R does not have a scalar type. "Scalars" in R are vectors with
 * one element, so this function cannot be used to distinguish between
 * vectors and scalars.)
 */
bool isInteger(Robj x) {
  return to!bool(Rf_isInteger(x));
}

/**
 * The most common way to pass multiple pieces of data in R is by putting
 * them into a list. If you pass a list from R to D, you need some way to
 * work with that data. If you want to return multiple items from D to R,
 * the only way to do that is with a list.
 * 
 * Those are the only two use cases for this struct.
 */
struct RList {
	/** 
	 * Needed for handling protection. You should not need to mess with this
	 * unless you know what you're doing. Might be made private in the future.
	 */
  ProtectedRObject data;
  
  /// Number of Robj held. Cannot be changed.
  int length;
  
  /// Names of objects. Lists in R can be accessed by name or index.
  string[] names;
  
  /** Used to make it more convenient to add new elements by name. Do not touch!
   *  Will probably be made private in the future.
   */
  int fillPointer = 0;
  private int counter = 0; // Used for foreach

	/**
	 * Create a new R list with `n` elements. The length can never be changed.
	 * This is a limitation on the R side. All we're doing here is calling
	 * `Rf_allocVector` in the R API to allocate a new list with `n` elements.
	 */
  this(int n) {
    Robj temp;
    Rf_protect(temp = Rf_allocVector(19, n));
    data = ProtectedRObject(temp, true);
    length = n;
    names = new string[n];
  }

  /** Call this to work with an existing R list. Creates a new R list with
   *  the same number of elements as `v`.
   * 
   * Params:
   * 	v = The R list you want to put into an `RList` struct. Normally this
   *    will be created on the R side and passed to D.
   *  u = Flag indicating whether or not to protect the list from the R
   *    garbage collector. Defaults to `false` because this function is
   *    normally called using an already existing R list that does not
   *    need protection.
   * 
   * $(TIP Anything inside an R list is automatically protected. If you
   * are creating an R list and plan to return it to R, you do not need
   * to worry about protecting anything inside the list.)
   */
  this(Robj v, bool u=false) {
    enforce(to!bool(Rf_isVectorList(v)), "Cannot pass a non-list to the constructor for an RList");
    data = ProtectedRObject(v, u);
    length = v.length;
    names = v.names;
    fillPointer = v.length;
  }
	
	/** Convenience method that allows you to create an RList from a list
	 *  in R by passing a string holding the R variable name.
	 * 
	 * Examples:
	 * 
	 * To pull `x` from R into D. Will throw an error if `x` is not a list.
	 * 
	 * ---
	 * auto y = RList("x");
	 * ---
	 */
  version(standalone) {
    this(string name) {
      this(evalR(name));
    }
  }
  
  /**
   * Allows access to the elements of an `RList` by index number or by name.
   * Note that it returns an `Robj`, which may or may not be protected. This
   * is an example of the intended use case:
   * 
   * Examples:
   * 
   * Create an RList from rx that is passed from R.
   * 
   * ```
   * auto x = RList(rx);
   * ```
   * 
   * Create an RMatrix from the first element in the list.
   * 
   * ```
   * auto m = RMatrix(x[0]);
   * ```
   * 
   * Create an RMatrix from the element named mat.
   * 
   * ```
   * auto m2 = RMatrix(x["mat"]);
   * ```
   */	
  Robj opIndex(int ii) {
    enforce(ii < length, "RList index has to be less than the number of elements");
    return VECTOR_ELT(data.robj, ii);
  }
  
  /// Ditto
	Robj opIndex(string name) {
    auto ind = countUntil!"a == b"(names, name);
    if (ind == -1) { enforce(false, "No element in the list with the name " ~ name); }
    return opIndex(ind.to!int);
	}
  
  /** If you want to add elements by index. Dangerous because there is
   *  nothing to prevent you from overwriting an existing element.
   */
  void unsafePut(Robj x, int ii) {
    enforce(ii < length, "RList index has to be less than the number of elements. Index " ~ to!string(ii) ~ " >= length " ~ to!string(length));
    SET_VECTOR_ELT(data.robj, ii, x);
  }
	
	/** Add an `Robj` to the end of the list and set the name to `name`.
	 *  Will throw an error if the RList is full.
	 */
  void put(Robj x, string name) {
    enforce(fillPointer < length, "RList is full - cannot add more elements");
    SET_VECTOR_ELT(data.robj, fillPointer, x);
    names[fillPointer] = name;
    fillPointer += 1;
  }
  
  /// Ditto	
  void put(Robj x) {
    put(x, "");
  }
	
	/**
	 * Can add an element by name. This is the idiomatic way to add elements
	 * to a list.
	 */
  void opIndexAssign(Robj x, string name) {
    put(x, name);
  }
	
	/// Ditto
  void opIndexAssign(RMatrix rm, string name) {
    put(rm.robj, name);
  }

	/// Ditto
  void opIndexAssign(RVector rv, string name) {
    put(rv.robj, name);
  }
  
	/// Ditto
  void opIndexAssign(RString rs, string name) {
    put(rs.robj, name);
  }
  
	/// Ditto
  void opIndexAssign(string s, string name) {
    put(s.robj, name);
  }
  
	/// Ditto
  void opIndexAssign(string[] sv, string name) {
    put(RStringArray(sv).robj, name);
  }
  
	/// Ditto
  void opIndexAssign(double v, string name) {
    put(v.robj, name);
  }
	
	/// Ditto
  void opIndexAssign(double[] vec, string name) {
    put(vec.robj, name);
  }
	
	/// Ditto
  void opIndexAssign(int v, string name) {
    put(v.robj, name);
  }
  
  /** Provided to make the RList a range. That allows iteration using
   *  a `foreach` loop.
   */
  bool empty() {
    return counter == length;
  }

	/// Ditto
  Robj front() {
    return this[counter];
  }

	/// Ditto
  void popFront() {
    counter += 1;
  }

	/** Use this to return an RList to R.
	 * 
	 * Examples:
	 * 
	 * ---
	 * return rl.robj;
	 * ---
	 */
  Robj robj() {
    setAttrib(data.robj, "names", names.robj);
    return data.robj;
  }
}

private struct NamedRObject {
  ProtectedRObject prot_robj;
  string name;
  
  Robj robj() {
    return prot_robj.robj;
  }
}

// This is here only for legacy purposes. It's functionality has been
// replaced by RList. Do not use!
deprecated("Do not use NamedList. Use RList instead. NamedList will be removed in the future.")
struct NamedList {
  NamedRObject[] data;
  
  // In case you have an RList and want to work with it as a NamedList
  // This will only be used when pulling in data from R
  // If you allocate an R list from D, it won't have names
  // Maybe that can be added in the future
  // Assumes it is protected
  this(Robj x) {
    enforce(to!bool(Rf_isVectorList(x)), "Cannot pass a non-list to the constructor for a NamedList");
    foreach(int ii, name; x.names) {
      data ~= NamedRObject(ProtectedRObject(VECTOR_ELT(x, ii)), name);
    }
  }
  
  version(standalone) {
    this(string name) {
      this(evalR(name));
    }
  }
  
  Robj robj() {
    auto rl = RList(to!int(data.length));
    foreach(val; data) {
      rl[val.name] = val.robj;
    }
    return rl.robj;
  }

  void print() {
    foreach(val; data) {
      writeln(val.name, ":");
      printR(val.robj);
      writeln("");
    }
  }
}

/** Copies a string allocated in R into a D string.
 * 
 * Params:
 * 	cstr = A string created in R and passed to D.
 * 
 * Examples:
 * 	
 * ```
 * # R code
 * title = "Chief Clown"
 * .Call("foo", title)
 * 
 * // D code
 * Robj foo(Robj r_title) {
 *   string d_title = r_title.toString(); // Copies "Chief Clown" into title.
 *   . . .
 * }
 * ```
 * 
 * See_Also: [stringArray]
 */
string toString(Robj cstr) {
  return to!string(R_CHAR(cstr));
}

/** Copies a string allocated in R from a character vector into a D string.
 * 
 * Params:
 * 	sv = A character vector created in R and passed to D.
 * 	ii = The index (starting at zero) holding the string to be copied into a D string.
 * 
 * 
 * Examples:
 * 	
 * ```
 * # R code
 * titles = c("Chief Clown", "Chief Joker", "Chief Nut")
 * .Call("foo", titles)
 * 
 * // D code
 * Robj foo(Robj r_titles) {
 *   string d_title = toString(r_titles, 1); // Copies "Chief Joker" into title.
 *   . . .
 * }
 * ```
 * 
 * See_Also: [stringArray]
 */
string toString(Robj sv, int ii) {
  return to!string(R_CHAR(STRING_ELT(sv, ii)));
}

/** Copies a string array from a character vector in R into a D string array.
 * 
 * Params:
 * 	sv = A character vector created in R and passed to D.
 * 
 * 
 * Examples:
 * 	
 * ```
 * # R code
 * titles = c("Chief Clown", "Chief Joker", "Chief Nut")
 * .Call("foo", titles)
 * 
 * // D code
 * Robj foo(Robj r_titles) {
 *   string[] d_titles = toString(r_titles, 1);
 *   . . .
 * }
 * ```
 * 
 * See_Also: [toString]
 */
string[] stringArray(Robj sv) {
  string[] result;
  foreach(ii; 0..Rf_length(sv)) {
    result ~= toString(sv, ii);
  }
  return result;
}

version(standalone) {
	/** Convenience function to pull the character vector `name` from R into D.
	 */
  string[] stringArray(string name) {
    Robj sv = evalR(name);
    string[] result;
    foreach(ii; 0..Rf_length(sv)) {
      result ~= toString(sv, ii);
    }
    return result;
  }
}

/** Support for passing strings from D to R and vice versa.
 * 
 *  Examples:
 *  
 *  ---
 *  string s = "Hello World";
 *  Robj rs = RString(s); // rs can be passed to R as rs.robj
 *  Robj rs = s.robj; // Same as the previous call
 *  ---
 * 
 *  $(NOTE While there is nothing wrong with using this struct directly,
 *  it is easier to just call `robj` on the string directly to pass it to
 *  R.)
 * 
 *  See_Also: [stringArray] and [toString] for passing strings from R into D.
 */
struct RString {
  ProtectedRObject data;
  
  this(string str) {
    Robj temp;
    Rf_protect(temp = Rf_allocVector(16, 1));
    data = ProtectedRObject(temp, true);
    SET_STRING_ELT(data.ptr, 0, Rf_mkChar(toUTFz!(char*)(str)));
  }

  Robj robj() {
    return data.ptr;
  }
}

/**
 * Not normally called unless you're working on the embedr library itself.
 * 
 * Returns an attribute from an R object, like the time series properties
 * on a ts object.
 */
Robj getAttrib(Robj x, string attr) {
  return Rf_getAttrib(x, RString(attr).robj);
}

/// Ditto
Robj getAttrib(ProtectedRObject x, string attr) {
  return Rf_getAttrib(x.ptr, RString(attr).robj);
}

/// Ditto
Robj getAttrib(Robj x, RString attr) {
  return Rf_getAttrib(x, attr.robj);
}

/// Ditto
Robj getAttrib(ProtectedRObject x, RString attr) {
  return Rf_getAttrib(x.ptr, attr.robj);
}

/**
 * If `x` has a `names` attribute attached to it,
 * this function will copy the names into a string[].
 * 
 * Throws an error if `names` is not defined for `x`.
 */
string[] names(Robj x) {
  return stringArray(getAttrib(x, "names"));
}

/**
 * Not normally called unless you're working on the embedr library itself.
 * 
 * Sets the value of an attribute on an R object, like the names of a list.
 */
void setAttrib(Robj x, string attr, ProtectedRObject val) {
  Rf_setAttrib(x, RString(attr).robj, val.robj);
}

/// Ditto
void setAttrib(Robj x, RString attr, ProtectedRObject val) {
  Rf_setAttrib(x, attr.robj, val.robj);
}

/// Ditto
void setAttrib(Robj x, string attr, Robj val) {
  Rf_setAttrib(x, RString(attr).robj, val);
}

/// Ditto
void setAttrib(Robj x, RString attr, Robj val) {
  Rf_setAttrib(x, attr.robj, val);
}

/**
 * Creates a new R object with room for one double value and copies `x` into it.
 */
Robj robj(double x) {
  return Rf_ScalarReal(x);
}

/**
 * Creates a new R object with room to hold `v.length` double values
 * and copies `v` into it.
 * 
 * See_Also: [RVector]
 */
Robj robj(double[] v) {
  return RVector(v).robj;
}

/**
 * Creates a new R object with room for one int value and copies `x` into it.
 */
Robj robj(int x) {
  return Rf_ScalarInteger(x);
}

/**
 * Creates a new R object with room for one string and copies `s` into it.
 * 
 * See_Also: [RString]
 */
Robj robj(string s) {
  return RString(s).robj;
}

/**
 * Creates a new R object with room to hold `sv.length` strings and copies `sv` into it.
 */
Robj robj(string[] sv) {
  return RStringArray(sv).robj;
}

ProtectedRObject RStringArray(string[] sv) {
  Robj temp;
  Rf_protect(temp = Rf_allocVector(16, to!int(sv.length)));
  auto result = ProtectedRObject(temp, true);
  foreach(ii; 0..to!int(sv.length)) {
    SET_STRING_ELT(result.robj, ii, Rf_mkChar(toUTFz!(char*)(sv[ii])));
  }
  return result;
}

/**
 * Returns the time series properties of an R object. If `rv` is not a
 * ts object, will throw an error.
 * 
 * The three elements of the output are the year, the time period (month,
 * quarter, etc.), and the frequency.
 */
ulong[3] tsp(Robj rv) {
  auto tsprop = RVector(getAttrib(rv, "tsp"));
  ulong[3] result;
  result[0] = lround(tsprop[0]*tsprop[2])+1;
  result[1] = lround(tsprop[1]*tsprop[2])+1;
  result[2] = lround(tsprop[2]);
  return result;
}

/**
 * Pull the value out of an R object holding one double value.
 * 
 * Examples:
 * 
 * ---
 * double x = rx.scalar;
 * double x = rx.scalar!double;
 * ---
 */
double scalar(Robj rx) {
  return Rf_asReal(rx); 
}

/// Ditto
double scalar(T: double)(Robj rx) {
  return Rf_asReal(rx);
}

/**
 * Pull the value out of an R object holding one int value.
 * 
 * Examples:
 * 
 * ---
 * int x = rx.scalar!int;
 * ---
 */
int scalar(T: int)(Robj rx) { 
  return Rf_asInteger(rx); 
}

/**
 * Pull the value out of an R object holding one int value.
 * 
 * Examples:
 * 
 * ---
 * long x = rx.scalar!long;
 * ---
 */
long scalar(T: long)(Robj rx) { 
  return to!long(rx.scalar!int); 
}

/**
 * Pull the value out of an R object holding one int value.
 * 
 * Examples:
 * 
 * ---
 * ulong x = rx.scalar!ulong;
 * ---
 */
ulong scalar(T: ulong)(Robj rx) { 
  return to!ulong(rx.scalar!int); 
}

/**
 * Pull the value out of an R object holding one string.
 * 
 * Examples:
 * 
 * ---
 * string x = rx.scalar!string;
 * ---
 */
string scalar(T: string)(Robj rx) { 
  return to!string(R_CHAR(STRING_ELT(rx,0))); 
}

version(standalone) {
/**
 * Convenience function to pull a double value out of R. Only used when
 * embedding an R interpreter inside a D program.
 * 
 * Examples:
 * 
 * ---
 * double x = scalar("rx"); // Copies rx from R into x in D
 * double x = scalar!double("rx"); // Same
 * double x = "rx".scalar!double; // Same
 * ---
 */
  double scalar(string name) {
    return Rf_asReal(evalR(name)); 
  }

	/// Ditto
	double scalar(T: double)(string name) {
		return Rf_asReal(evalR(name)); 
	}

	/**
	 * Convenience function to pull an int value out of R. Only used when
	 * embedding an R interpreter inside a D program.
	 * 
	 * Examples:
	 * 
	 * ---
	 * int x = scalar!int("rx");
	 * int x = "rx".scalar!int; // Same thing
	 * ---
	 */
	int scalar(T: int)(string name) { 
		return Rf_asInteger(evalR(name)); 
	}

	/**
	 * Convenience function to pull an int value out of R. Only used when
	 * embedding an R interpreter inside a D program.
	 * 
	 * Examples:
	 * 
	 * ---
	 * long x = scalar!long("rx");
	 * long x = "rx".scalar!long; // Same thing
	 * ---
	 */
	long scalar(T: long)(string name) { 
		return to!long(evalR(name).scalar!int); 
	}

	/**
	 * Convenience function to pull an int value out of R. Only used when
	 * embedding an R interpreter inside a D program.
	 * 
	 * Examples:
	 * 
	 * ---
	 * ulong x = scalar!ulong("rx");
	 * ulong x = "rx".scalar!ulong; // Same thing
	 * ---
	 */
	ulong scalar(T: ulong)(string name) { 
		return to!ulong(evalR(name).scalar!int); 
	}

	/**
	 * Convenience function to pull a string out of R. Only used when
	 * embedding an R interpreter inside a D program.
	 * 
	 * Examples:
	 * 
	 * ---
	 * string s = scalar!string("rs");
	 * string s = "rs".scalar!string; // Same thing
	 * ---
	 */
	string scalar(T: string)(string name) { 
		return to!string(R_CHAR(STRING_ELT(evalR(name),0))); 
	}
}

/**
 * This struct is used to work with a matrix that has been
 * allocated in R. A pointer to the data is held, along with
 * the dimensions. An `RMatrix` struct is reference counted
 * to take care of protecting it from the R garbage collector
 * while in use, and unprotecting when it is no longer used,
 * as necessary.
 * 
 * You can refer to elements using standard matrix notation, i.e.,
 * `x[1,4]`. No matrix operations are provided, as this struct exists
 * only to facilitate the passing of data, and each user will have
 * her own preferred way to do things like matrix multiplication.
 */
struct RMatrix {
  ProtectedRObject data;
  int rows;
  int cols;
  double * ptr;
  
  /**
   * Allocate a new matrix in R and create a new `RMatrix` to wrap it,
   * with protection from the R garbage collector.
   * 
   * Examples:
   * 
   * ---
   * auto m = RMatrix(300, 4);
   * ---
   */
  this(int r, int c) {
    Robj temp;
    Rf_protect(temp = Rf_allocMatrix(14, r, c));
    data = ProtectedRObject(temp, true);
    ptr = REAL(temp);
    rows = r;
    cols = c;
  }
  
  /**
   * Allocate a new matrix in R and copy in the values of a
   * `GretlMatrix` or `DoubleMatrix` if using the dmdgretl library
   * for matrix algebra.
   * 
   * Examples:
   * 
   * ---
   * auto m = RMatrix(gm); // gm is a GretlMatrix
   * ---
   */
  version(gretl) {
    this(T)(T m) if (is(T == DoubleMatrix) || is(T == GretlMatrix)) {
      Robj temp;
      Rf_protect(temp = Rf_allocMatrix(14, m.rows, m.cols));
      data = ProtectedRObject(temp, true);
      ptr = REAL(temp);
      rows = m.rows;
      cols = m.cols;
      ptr[0..m.rows*m.cols] = m.ptr[0..m.rows*m.cols];
    }
  }

	/**
	 * If using the dmdgretl library for matrix algebra, allocate a
	 * new matrix in R and copy the elements of the matrix into it.
	 * 
	 * Examples:
	 * 
	 * ---
	 * RMatrix m = gm.mat;
	 * ---
	 */
  version(gretl) {
    GretlMatrix mat() {
      GretlMatrix result;
      result.rows = this.rows;
      result.cols = this.cols;
      result.ptr = this.ptr;
      return result;
    }
  	
    alias mat this;
  }

  /**
   * Work with an `Robj` struct directly. This should only be used
   * if you fully understand the internals of this library.
   * 
   * Params:
   *   rm = An R object holding a matrix.
   *   u  = Flag to indicate whether `rm` should be unprotected when it
   *        is no longer used
   */
  this(Robj rm, bool u=false) {
    enforce(isMatrix(rm), "Constructing RMatrix from something not a matrix"); 
    enforce(isNumeric(rm), "Constructing RMatrix from something that is not numeric");
    data = ProtectedRObject(rm, u);
    ptr = REAL(rm);
    rows = Rf_nrows(rm);
    cols = Rf_ncols(rm);
  }
  
  /**
   * If embedding an R interpreter inside a D program, this function
   * makes it more convenient to pull a matrix from R into D.
   * 
   * Examples:
   * 
   * ---
   * auto rm = RMatrix("m");
   * ---
   */
  version(standalone) {
    this(string name) {
      this(evalR(name));
    }
  }
	
  // Use this only with objects that don't need protection
  // For "normal" use that's not an issue
  this(ProtectedRObject rm) {
    this(rm.ptr);
  }
	
	/**
	 * Create a reference to an RVector and access it as a matrix.
	 * In R, matrix and vector types are different.
	 */
  this(RVector v) {
    data = v.data;
    rows = v.rows;
    cols = 1;
    ptr = v.ptr;
  }

	/**
	 * Standard matrix indexing is possible.
	 */
  double opIndex(int r, int c) {
    enforce(r < this.rows, "First index exceeds the number of rows");
    enforce(c < this.cols, "Second index exceeds the number of columns");
    return ptr[c*this.rows+r];
  }

	/// Ditto
  void opIndexAssign(double v, int r, int c) {
    ptr[c*rows+r] = v;
  }

	/**
	 * Set all values of a matrix equal to `val`.
	 * 
	 * Examples:
	 * 
	 * ---
	 * rm = 1.5;
	 * ---
	 */
  void opAssign(double val) {
    ptr[0..this.rows*this.cols] = val;
  }
  
  /**
   * Copy the values of `m` into a new matrix.
   */
  void opAssign(RMatrix m) {
    Robj temp;
    Rf_protect(temp = Rf_allocMatrix(14, m.rows, m.cols));
    data = ProtectedRObject(temp, true);
    ptr = REAL(temp);
    rows = m.rows;
    cols = m.cols;
    ptr[0..m.rows*m.cols] = m.ptr[0..m.rows*m.cols];
  }

	/// Ditto
  version(gretl) {
    void opAssign(T)(T m) if (is(T == DoubleMatrix) || is(T == GretlMatrix)) {
      enforce(rows == m.rows, "Number of rows in source (" ~ to!string(m.rows) ~ ") is different from number of rows in destination (" ~ rows ~ ").");
      enforce(cols == m.cols, "Number of columns in source (" ~ to!string(m.rows) ~ ") is different from number of columns in destination (" ~ rows ~ ").");
      ptr[0..m.rows*m.cols] = m.ptr[0..m.rows*m.cols];
    }
  }

	/**
	 * Get the underlying `Robj` that will be returned to R.
	 */
  Robj robj() {
    return data.robj;
  }
}

/**
 * Print a matrix, with an optional message.
 * 
 * Examples:
 * 
 * ---
 * rm.print("Covariance matrix");
 * rm.print();
 * ---
 */
void print(RMatrix m, string msg="") {
  writeln(msg);
  foreach(row; 0..m.rows) {
    foreach(col; 0..m.cols) {
      write(m[row,col], " ");
    }
    writeln("");
  }
}

/**
 * Create a copy of a matrix.
 * 
 * Examples:
 * 
 * ---
 * RMatrix rm2 = rm.dup;
 * ---
 */
RMatrix dup(RMatrix rm) { 
  RMatrix result = RMatrix(Rf_protect(Rf_duplicate(rm.robj)), true);
  return result;
}

/**
 * This struct is used to work with a vector that has been
 * allocated in R. A pointer to the data is held, along with
 * the dimensions. An `RVector` struct is reference counted
 * to take care of protecting it from the R garbage collector
 * while in use, and unprotecting when it is no longer used,
 * as necessary.
 * 
 * You can refer to elements using standard vector notation, i.e.,
 * `v[4]`.
 * 
 * $(NOTE Vectors and matrices are different objects in R.)
 */
struct RVector {
  int rows;
  double * ptr;
  ProtectedRObject data;
  
  /**
   * Create a reference to the data in a matrix with one column.
   */
  version(gretl) {
    GretlMatrix mat() {
      GretlMatrix result;
      result.rows = this.rows;
      result.cols = 1;
      result.ptr = this.ptr;
      return result;
    }
		
    alias mat this;
  }
  
  /**
   * Allocate a vector with room for 30 elements in R.
   * 
   * Examples:
   * 
   * ---
   * auto v = RVector(50);
   * ---
   */
  this(int r) {
    Robj temp;
    Rf_protect(temp = Rf_allocVector(14,r));
    data = ProtectedRObject(temp, true);
    rows = r;
    ptr = REAL(temp);
  }

  /**
   * You should only use this function if you understand the internal
   * workings of this library.
   */
  this(Robj rv, bool u=false) {
    enforce(isVector(rv), "In RVector constructor: Cannot convert non-vector R object to RVector");
    enforce(isNumeric(rv), "In RVector constructor: Cannot convert non-numeric R object to RVector");
    data = ProtectedRObject(rv, u);
    rows = rv.length;
    ptr = REAL(rv);
  }
  
  /**
   * Pull a vector from an R interpreter embedded inside a D program.
   * 
   * Examples:
   * 
   * ---
   * auto v = RVector("vec");
   * ---
   */
  version(standalone) {
    this(string name) {
      this(evalR(name));
    }
  }	
  
  this(ProtectedRObject rv, bool u=false) {
    this(rv.robj, u);
  }

  /**
   * Allocates a new vector in R with `v.length` elements
   * and copies the elements of `v` into it.
   * 
   * Examples:
   * 
   * Create an `RVector` from a `double[]`.
   * 
   * ---
   * auto v = RVector([1.2, 3.4, 5.6, 7.8]);
   * ---
   */
  this(T)(T v) {
    Robj temp;
    Rf_protect(temp = Rf_allocVector(14, to!int(v.length)));
    data = ProtectedRObject(temp, true);
    rows = to!int(v.length);
    ptr = REAL(temp);
    foreach(ii; 0..to!int(v.length)) {
      ptr[ii] = v[ii];
    }
  }

  /**
   * Examples:
   * 
   * ---
   * double x = v[7];
   * ---
   */
  double opIndex(int r) {
    enforce(r < rows, "Index out of range: index on RVector is too large");
    return ptr[r];
  }
  
  /**
   * Pull out the elements with index values in `obs`.
   * 
   * Examples:
   * 
   * ---
   * auto v = RVector([1.1, 2.2, 3.3, 4.4, 5.5]);
   * RVector v2 = v[[0, 2, 4]]; // holds [1.1, 3.3, 5.5]
   * ---
   */
  RVector opIndex(int[] obs) {
		auto result = RVector(to!int(obs.length));
		foreach(ii; 0..to!int(obs.length)) {
			result[ii] = this[obs[ii]];
		}
		return result;
	}

  /**
   * Examples:
   * 
   * ---
   * v[2] = 3.48;
   * ---
   */
  void opIndexAssign(double v, int r) {
    enforce(r < rows, "Index out of range: index on RVector is too large");
    ptr[r] = v;
  }

  /**
   * Examples:
   * 
   * --- 
   * RVector v;
   * v = [1.2, 3.4, 5.6];
   * ---
   */
  void opAssign(T)(T x) {
    enforce(x.length == rows, "Cannot assign to RVector from an object of a different length");
    foreach(ii; 0..to!int(x.length)) {
      this[ii] = x[ii];
    }
  }
  
  /**
   * Returns a reference to a slice of an RVector as a new RVector.
   * 
   * $(WARNING For efficiency purposes, `opSlice` holds a reference
   * to the data, so what happens if the original RVector is unprotected
   * is undefined behavior.)
   * 
   * Examples:
   * 
   * ---
   * auto v = RVector([1.1, 2.2, 3.3, 4.4, 5.5]);
   * RVector y = v[0..2]; // holds [1.1, 2.2]
   * ---
   */
  RVector opSlice(int i, int j) {
    enforce(j <= rows, "Index out of range: index on RVector slice is too large. index=" ~ to!string(j) ~ " # rows=" ~ to!string(rows));
    enforce(i < j, "First index has to be less than second index");
    RVector result = this;
    result.rows = j-i;
    result.ptr = &ptr[i];
    result.data = data;
    return result;
  }

  /**
   * Prints the contents of an `RVector` struct with an optional message.
   * 
   * Examples:
   * 
   * ---
   * v.print("Oil price");
   * v.print();
   * ---
   */
  void print(string msg="") {
    if (msg != "") { writeln(msg, ":"); }
    foreach(val; this) {
      writeln(val);
    }
  }

  /**
   * Returns the number of elements.
   */
  int length() {
    return rows;
  }
	
  /**
   * `RVector` is a range. You can use it with foreach.
   * 
   * Examples:
   * 
   * ---
   * auto v = RVector([1.1, 2.2, 3.3, 4.4, 5.5]);
   * foreach(val; v) {
   *   writeln(val);
   * }
   * ---
   */
  bool empty() {
    return rows == 0;
  }

  /// Ditto
  double front() {
    return this[0];
  }

  /// Ditto
  void popFront() {
    ptr = &ptr[1];
    rows -= 1;
  }

  /**
   * Create a new `double[]` and copy the contents of the
   * current `RVector` into it.
   * 
   * Examples:
   * 
   * ---
   * auto v = RVector([1.1, 2.2, 3.3, 4.4, 5.5]);
   * double[] arr = v.array;
   * ---
   */ 
  double[] array() {
    double[] result;
    result.reserve(rows);
    foreach(val; this) {
      result ~= val;
    }
    return result;
  }

	/**
	 * Get the underlying `Robj` that will be returned to R.
	 */
  Robj robj() {
    return data.robj;
  }
}

/**
 * Returns element `ii` from the bottom.
 * 
 * Examples:
 * 
 * Return the last element.
 * 
 * ---
 * double d = v.fromLast(0);
 * ---
 * 
 * Return the element three positions before the end.
 * 
 * ---
 * double d = v.fromLast(3);
 * ---
 */
double fromLast(RVector rv, int ii) {
	return rv[rv.length-ii-1];
}

/**
 * Returns the last element of an `RVector`.
 */
double last(RVector rv) {
	return rv[rv.length-1];
}

/**
 * Same as `RVector`, but holds a vector of integers instead of a
 * vector of doubles.
 */
struct RIntVector {
  ProtectedRObject data;
  ulong length;
  int * ptr;

  /**
   * Allocate a new integer vector with `r` elements.
   */
  this(int r) {
    Robj temp;
    Rf_protect(temp = Rf_allocVector(13, r));
    data = ProtectedRObject(temp, true);
    length = r;
    ptr = INTEGER(temp);
  }

  /**
   * Allocate a new integer vector in R and copy the elements of `v`
   * into it.
   */
  this(int[] v) {
    Robj temp;
    Rf_protect(temp = Rf_allocVector(13, to!int(v.length)));
    data = ProtectedRObject(temp);
    length = v.length;
    ptr = INTEGER(temp);
    foreach(int ii, val; v) {
      this[ii] = val;
    }
  }

  /**
   * Only call this if you understand the internals of this library.
   */
  this(Robj rv, bool u=false) {
    enforce(isVector(rv), "In RVector constructor: Cannot convert non-vector R object to RVector");
    enforce(isInteger(rv), "In RVector constructor: Cannot convert non-integer R object to RVector");
    data = ProtectedRObject(rv);
    length = rv.length;
    ptr = INTEGER(rv);
  }

  /**
   * Can do standard indexing of an `RIntVector`.
   */
  int opIndex(int obs) {
    enforce(obs < length, "Index out of range: index on RIntVector is too large");
    return ptr[obs];
  }

  /// Ditto
  void opIndexAssign(int val, int obs) {
    enforce(obs < length, "Index out of range: index on RIntVector is too large");
    ptr[obs] = val;
  }

  /// Ditto
  void opAssign(int[] v) {
    foreach(int ii, val; v) {
      this[ii] = val;
    }
  }

  /**
   * Returns a reference to a slice of an RIntVector as a new RIntVector.
   * 
   * $(WARNING For efficiency purposes, `opSlice` holds a reference
   * to the data, so what happens if the original RIntVector is unprotected
   * is undefined behavior.)
   * 
   * Examples:
   * 
   * ---
   * auto v = RIntVector([1, 2, 3, 4, 5]);
   * RVector y = v[0..2]; // holds [1, 2]
   * ---
   */
  RIntVector opSlice(int i, int j) {
    enforce(j < length, "Index out of range: index on RIntVector slice is too large");
    enforce(i < j, "First index on RIntVector slice has to be less than the second index");
    RIntVector result;
    result.data = data;
    result.length = j-i;
    result.ptr = &ptr[i];
    return result;
  }

  /**
   * Create a new `int[]` and copy the contents of the
   * current `RIntVector` into it.
   * 
   * Examples:
   * 
   * ---
   * auto v = RIntVector([1, 2, 3, 4, 5]);
   * int[] arr = v.array;
   * ---
   */ 
  int[] array() {
    int[] result;
    result.reserve(length);
    foreach(val; this) {
      result ~= val;
    }
    return result;
  }

  /**
   * Prints the contents of an `RVector` struct with an optional message.
   * 
   * Examples:
   * 
   * ---
   * v.print("Index values");
   * v.print();
   * ---
   */
  void print() {
    foreach(val; this) {
      writeln(val);
    }
  }

  /**
   * `RIntVector` is a range.
   */
  bool empty() {
    return length == 0;
  }

  /// Ditto
  int front() {
    return this[0];
  }

  /// Ditto
  void popFront() {
    ptr = &ptr[1];
    length -= 1;
  }
  
	/**
	 * Get the underlying `Robj` that will be returned to R.
	 */
  Robj robj() {
    return data.robj;
  }
}

/**
 * This function adds the boilerplate needed inside a shared library
 * that will be called from R.
 * 
 * Params:
 *   name = The name of the library
 * 
 * $(NOTE R requires the name of the library to start with `lib`.)
 * 
 * Examples:
 * 
 * Adds boilerplate to create a library named libfoo.
 * 
 * ---
 * createRLibrary("foo");
 * ---
 */
string createRLibrary(string name) {
	return "import core.runtime;
struct DllInfo;
export extern(C) {
  void R_init_lib" ~ name ~ "(DllInfo * info) {
    Runtime.initialize();
  }
  
  void R_unload_lib" ~ name ~ "(DllInfo * info) {
    Runtime.terminate();
  }
}
";
}

/** Constants pulled from the R API, for compatibility
 */
immutable double M_E=2.718281828459045235360287471353;
immutable double M_LOG2E=1.442695040888963407359924681002;
immutable double M_LOG10E=0.434294481903251827651128918917;
immutable double M_LN2=0.693147180559945309417232121458;
immutable double M_LN10=2.302585092994045684017991454684; 
immutable double M_PI=3.141592653589793238462643383280;
immutable double M_2PI=6.283185307179586476925286766559; 
immutable double M_PI_2=1.570796326794896619231321691640;
immutable double M_PI_4=0.785398163397448309615660845820;
immutable double M_1_PI=0.318309886183790671537767526745;
immutable double M_2_PI=0.636619772367581343075535053490;
immutable double M_2_SQRTPI=1.128379167095512573896158903122;
immutable double M_SQRT2=1.414213562373095048801688724210;
immutable double M_SQRT1_2=0.707106781186547524400844362105;
immutable double M_SQRT_3=1.732050807568877293527446341506;
immutable double M_SQRT_32=5.656854249492380195206754896838;
immutable double M_LOG10_2=0.301029995663981195213738894724;
immutable double M_SQRT_PI=1.772453850905516027298167483341;
immutable double M_1_SQRT_2PI=0.398942280401432677939946059934;
immutable double M_SQRT_2dPI=0.797884560802865355879892119869;
immutable double M_LN_SQRT_PI=0.572364942924700087071713675677;
immutable double M_LN_SQRT_2PI=0.918938533204672741780329736406;
immutable double M_LN_SQRT_PId2=0.225791352644727432363097614947;

extern (C) {
  double * REAL(Robj x);
  int * INTEGER(Robj x);
  const(char) * R_CHAR(Robj x);
  int * LOGICAL(Robj x);
  Robj STRING_ELT(Robj x, int i);
  Robj VECTOR_ELT(Robj x, int i);
  Robj SET_VECTOR_ELT(Robj x, int i, Robj v);
  void SET_STRING_ELT(Robj x, int i, Robj v);
  int Rf_length(Robj x);
  int Rf_ncols(Robj x);
  int Rf_nrows(Robj x);
  extern __gshared Robj R_NilValue;
  alias RNil = R_NilValue;
  
  void Rf_PrintValue(Robj x);
  int Rf_isArray(Robj x);
  int Rf_isInteger(Robj x);
  int Rf_isList(Robj x);
  int Rf_isLogical(Robj x);
  int Rf_isMatrix(Robj x);
  int Rf_isNull(Robj x);
  int Rf_isNumber(Robj x);
  int Rf_isNumeric(Robj x);
  int Rf_isReal(Robj x);
  int Rf_isVector(Robj x);
  int Rf_isVectorList(Robj x);
  Robj Rf_protect(Robj x);
  Robj Rf_unprotect(int n);
  Robj Rf_unprotect_ptr(Robj x);
  Robj Rf_listAppend(Robj x, Robj y);
  Robj Rf_duplicate(Robj x);
  double Rf_asReal(Robj x);
  int Rf_asInteger(Robj x);
  Robj Rf_ScalarReal(double x);
  Robj Rf_ScalarInteger(int x);
  Robj Rf_getAttrib(Robj x, Robj attr);
  Robj Rf_setAttrib(Robj x, Robj attr, Robj val);
  Robj Rf_mkChar(const char * str);
  void Rf_error(const char * msg);
  void R_CheckUserInterrupt();
    
  // type is 0 for NILSXP, 13 for integer, 14 for real, 19 for VECSXP
  Robj Rf_allocVector(uint type, int n);
  Robj Rf_allocMatrix(uint type, int rows, int cols);
        
  // I don't use these, and don't know enough about them to mess with them
  // They are documented in the R extensions manual.
  double gammafn(double);
  double lgammafn(double);
  double lgammafn_sign(double, int *);
  double digamma(double);
  double trigamma(double);
  double tetragamma(double);
  double pentagamma(double);
  double beta(double, double);
  double lbeta(double, double);
  double choose(double, double);
  double lchoose(double, double);
  double bessel_i(double, double, double);
  double bessel_j(double, double);
  double bessel_k(double, double, double);
  double bessel_y(double, double);
  double bessel_i_ex(double, double, double, double *);
  double bessel_j_ex(double, double, double *);
  double bessel_k_ex(double, double, double, double *);
  double bessel_y_ex(double, double, double *);
        
        
  /** Calculate exp(x)-1 for small x */
  double expm1(double);
        
  /** Calculate log(1+x) for small x */
  double log1p(double);
        
  /** Returns 1 for positive, 0 for zero, -1 for negative */
  double sign(double x);
        
  /** |x|*sign(y)
   *  Gives x the same sign as y
   */   
  double fsign(double x, double y);
        
  /** R's signif() function */
  double fprec(double x, double digits);
        
  /** R's round() function */
  double fround(double x, double digits);
        
  /** Truncate towards zero */
  double ftrunc(double x);
        
  /** Same arguments as the R functions */ 
  double dnorm4(double x, double mu, double sigma, int give_log);
  double pnorm(double x, double mu, double sigma, int lower_tail, int log_p);
  double qnorm(double p, double mu, double sigma, int lower_tail, int log_p);
  void pnorm_both(double x, double * cum, double * ccum, int i_tail, int log_p); /* both tails */
  /* i_tail in {0,1,2} means: "lower", "upper", or "both" :
     if(lower) return *cum := P[X <= x]
     if(upper) return *ccum := P[X > x] = 1 - P[X <= x] */

  /** Same arguments as the R functions */ 
  double dunif(double x, double a, double b, int give_log);
  double punif(double x, double a, double b, int lower_tail, int log_p);
  double qunif(double p, double a, double b, int lower_tail, int log_p);

  /** These do not allow for passing argument rate as in R 
      Confirmed that otherwise you call them the same as in R */
  double dgamma(double x, double shape, double scale, int give_log);
  double pgamma(double q, double shape, double scale, int lower_tail, int log_p);
  double qgamma(double p, double shape, double scale, int lower_tail, int log_p);
        
  /** Unless otherwise noted from here down, if the argument
   *  name is the same as it is in R, the argument is the same.
   *  Some R arguments are not available in C */
  double dbeta(double x, double shape1, double shape2, int give_log);
  double pbeta(double q, double shape1, double shape2, int lower_tail, int log_p);
  double qbeta(double p, double shape1, double shape2, int lower_tail, int log_p);

  /** Use these if you want to set ncp as in R */
  double dnbeta(double x, double shape1, double shape2, double ncp, int give_log);
  double pnbeta(double q, double shape1, double shape2, double ncp, int lower_tail, int log_p);
  double qnbeta(double p, double shape1, double shape2, double ncp, int lower_tail, int log_p);

  double dlnorm(double x, double meanlog, double sdlog, int give_log);
  double plnorm(double q, double meanlog, double sdlog, int lower_tail, int log_p);
  double qlnorm(double p, double meanlog, double sdlog, int lower_tail, int log_p);

  double dchisq(double x, double df, int give_log);
  double pchisq(double q, double df, int lower_tail, int log_p);
  double qchisq(double p, double df, int lower_tail, int log_p);

  double dnchisq(double x, double df, double ncp, int give_log);
  double pnchisq(double q, double df, double ncp, int lower_tail, int log_p);
  double qnchisq(double p, double df, double ncp, int lower_tail, int log_p);

  double df(double x, double df1, double df2, int give_log);
  double pf(double q, double df1, double df2, int lower_tail, int log_p);
  double qf(double p, double df1, double df2, int lower_tail, int log_p);

  double dnf(double x, double df1, double df2, double ncp, int give_log);
  double pnf(double q, double df1, double df2, double ncp, int lower_tail, int log_p);
  double qnf(double p, double df1, double df2, double ncp, int lower_tail, int log_p);

  double dt(double x, double df, int give_log);
  double pt(double q, double df, int lower_tail, int log_p);
  double qt(double p, double df, int lower_tail, int log_p);

  double dnt(double x, double df, double ncp, int give_log);
  double pnt(double q, double df, double ncp, int lower_tail, int log_p);
  double qnt(double p, double df, double ncp, int lower_tail, int log_p);

  double dbinom(double x, double size, double prob, int give_log);
  double pbinom(double q, double size, double prob, int lower_tail, int log_p);
  double qbinom(double p, double size, double prob, int lower_tail, int log_p);

  double dcauchy(double x, double location, double scale, int give_log);
  double pcauchy(double q, double location, double scale, int lower_tail, int log_p);
  double qcauchy(double p, double location, double scale, int lower_tail, int log_p);
        
  /** scale = 1/rate */
  double dexp(double x, double scale, int give_log);
  double pexp(double q, double scale, int lower_tail, int log_p);
  double qexp(double p, double scale, int lower_tail, int log_p);

  double dgeom(double x, double prob, int give_log);
  double pgeom(double q, double prob, int lower_tail, int log_p);
  double qgeom(double p, double prob, int lower_tail, int log_p);

  double dhyper(double x, double m, double n, double k, int give_log);
  double phyper(double q, double m, double n, double k, int lower_tail, int log_p);
  double qhyper(double p, double m, double n, double k, int lower_tail, int log_p);

  double dnbinom(double x, double size, double prob, int give_log);
  double pnbinom(double q, double size, double prob, int lower_tail, int log_p);
  double qnbinom(double p, double size, double prob, int lower_tail, int log_p);

  double dnbinom_mu(double x, double size, double mu, int give_log);
  double pnbinom_mu(double q, double size, double mu, int lower_tail, int log_p);

  double dpois(double x, double lambda, int give_log);
  double ppois(double x, double lambda, int lower_tail, int log_p);
  double qpois(double p, double lambda, int lower_tail, int log_p);

  double dweibull(double x, double shape, double scale, int give_log);
  double pweibull(double q, double shape, double scale, int lower_tail, int log_p);
  double qweibull(double p, double shape, double scale, int lower_tail, int log_p);

  double dlogis(double x, double location, double scale, int give_log);
  double plogis(double q, double location, double scale, int lower_tail, int log_p);
  double qlogis(double p, double location, double scale, int lower_tail, int log_p);

  double ptukey(double q, double nranges, double nmeans, double df, int lower_tail, int log_p);
  double qtukey(double p, double nranges, double nmeans, double df, int lower_tail, int log_p);
}

