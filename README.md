シェルスクリプト（Bashスクリプト）でかんたんな自作言語のコンパイラを書いた  
https://qiita.com/sonota88/items/79dd2b0c1dae776c56d9

```
$ LANG=C bash --version | grep bash
GNU bash, version 4.4.20(1)-release (x86_64-pc-linux-gnu)
```

```
git clone --recursive https://github.com/sonota88/vm2gol-v2-bash.git
cd vm2gol-v2-bash
./test.sh all
```
