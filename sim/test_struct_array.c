struct Point {
    int x;
    int y;
};

int main() {
    struct Point p1;
    p1.x = 10;
    p1.y = 20;
    
    struct Point p2;
    p2 = p1; 
    
    int arr[5];
    arr[0] = p2.x;
    arr[1] = p2.y;
    
    int sum;
    sum = arr[0] + arr[1];
    
    return sum;
}
