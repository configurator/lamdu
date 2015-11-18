# Project Lamdu

[![Join the chat at https://gitter.im/lamdu/lamdu](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/lamdu/lamdu?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

This project aims to create a "next-generation", "live programming" environment that radically improves the programming experience.

See the [Main Page](http://peaker.github.io/lamdu/)


## Installation

#### osx

requires [stack](https://github.com/commercialhaskell/stack/releases), [brew](http://brew.sh/) and [git](https://git-scm.com/):

```shell
brew install ftgl leveldb
git clone --recursive https://github.com/lamdu/lamdu
cd lamdu
stack setup
stack install

```

#### ubuntu

requires [stack](https://github.com/commercialhaskell/stack/releases)
```shell
sudo apt-get update -qq
sudo apt-get install git libftgl-dev libleveldb-dev libglfw-dev libxrandr-dev libxi-dev libxcursor-dev libxinerama-dev -yq
git clone --recursive https://github.com/lamdu/lamdu
cd lamdu
stack setup
stack install

```

## Tutorial

At the top we have an interactive shell, where we can type calculations.

![Golden ratio example](https://i.imgur.com/vbPRcCO.png)

To type the calculation above:

* type "**`1+s`**"
* at this point we apply the addition operator to the number 1 and are picking the other argument to the addition. we are offered different options which contain the string "s" in their names
* pick the option we desire ("sqrt _") by filtering the option by typing and navigating to it with the cursor keys, and then pressing **space** (as of writing this, it is the first option offered, partly due to a currently minimal library of available functions).
* type "**`5`**" and press **space**
* select the whole expression by pressing **shift+left** twice
* type "**`/2`**" and press **space**

Directly under each expression in the code we see annotations of its evaluation results. Some annotations are more far apart from the expression's code due to its subexpression's annotation appearing between them.

So as to not expand the expression, some annotations are shrunk. In this case `sqrt 5`'s annotation is shrunk. To see it in normal size - simply navigate to this expression, by going to the `sqrt` or `5` and pressing **shift+left**.
