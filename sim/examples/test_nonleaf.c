int add(int a, int b) {
    return a + b;
}

int complex(int a, int b) {
    int c = add(a, b);
    return c + 1;
}

void main() {
    int res = complex(5, 10);
}
