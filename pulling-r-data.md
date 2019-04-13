# Pulling R Data Into D

The motivation for embedding an R interpreter inside your D program is that it gives you access to the full R ecosystem. 

Suppose you're processing data in a D program, and after the dataset is prepared, you want to estimate the logit model in [this example](https://stats.idre.ucla.edu/r/dae/logit-regression/). After estimation, you want to do further analysis of the vector of residuals. Phobos doesn't provide a logit model estimation function, so you decide to sending the data to R to do the estimation.

The variables `admit`, `gre`, `gpa`, and `rank` all exist in your D program as `double[]` arrays. You copy the data into R, creating new R variables in the process:

```
admit.toR("admit");
gre.toR("gre");
gpa.toR("gpa");
rank.toR("rank");
```

Then you estimate the model:

```
evalRQ(`mylogit <- glm(admit ~ gre + gpa + rank, family = "binomial")`);
```

It is tempting to make the residual vector available to your D program by creating an RVector:

```
auto res = RVector("residuals(mylogit)");
```

That *might* work, and it will even *probably* work (as in 99.8% of the time). Occasionally, though, it might not. It's tempting to do that because all you're doing is passing one pointer from R to D for efficiency.

The problem is that there is no guarantee that an object allocated in R and won't change. (In this case, I can't think of any way the underlying data might change, but in general you can't assume that it won't.) For safety purposes, you should make a copy of the data, for instance

```
double[] res = RVector("residuals(mylogit)").array;
```

For full details, and more information about when this can cause problems, see [this discussion](https://cran.r-project.org/doc/manuals/r-release/R-exts.html#Named-objects-and-copying) in the R Extensions manual. Copying is sometimes an expensive operation. If you can't afford it, you probably shouldn't be calling into R.
