def f(l, t, a, b, c):
    if t > l:
        return None
    if a * (l - t) + b * c <= (b - a) * t:
        return l, t
    else:
        return f(l, t+1, a, b, c)

for l in range(1,20):
    print('Keeper', f(l, 0, 1, 2, 1))
    print('Watcher 3/4 + 1',f(l, 0, 3, 4, 1))
    print()

exit()
l = 10
c = 1
for a in range(0, 20):
    for b in range(0, 20):
        output = f(l, 0, a, b, c)
        if output is not None:
            if b - a != 0:
                val = b * c // (b - a)
                if val >= 4 and val < 8:
                    if a/b > 0.5 and a/b < 0.8:
                        print(a,b,c, output, a/b)
