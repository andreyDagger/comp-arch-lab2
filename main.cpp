#include <iostream>

#define M 64
#define N 60
#define K 32
#define int8 char
#define int16 short
#define int unsigned int

const int OFFSET = 5;
const int LINE_COUNT = 1 << 5;
const int LINE_SIZE = 1 << 5;
const int TAG_SIZE = 11;
const int SET_COUNT = 1 << 4;
int mem[M * K + K * N * 2 + M * N * 4];
int data[SET_COUNT][LINE_COUNT / SET_COUNT][LINE_SIZE];
int line_tag[SET_COUNT][LINE_COUNT / SET_COUNT];
int valid[SET_COUNT][LINE_COUNT / SET_COUNT];
int dirty[SET_COUNT][LINE_COUNT / SET_COUNT];
int time[SET_COUNT][LINE_COUNT / SET_COUNT];

int timer = 0;
int full = 0;
int cnt = 0;
int tacts = 0;

void push(int set, int i) {
    for (int j = 0; j < LINE_SIZE; j++) {
        int val = data[set][i][j];
        int address = j | (set << 5) | (line_tag[set][i] << 9);
        mem[address] = val;
    }
    dirty[set][i] = 0;
    valid[set][i] = 0;
}

void write_from_ram_to_line(int set, int line_idx, int start, int tag) {
    tacts += 100;
    line_tag[set][line_idx] = tag;
    time[set][line_idx] = timer;
    for (int j = start; j < start + LINE_SIZE; j++) {
        data[set][line_idx][j % LINE_SIZE] = mem[j];
    }
    dirty[set][line_idx] = 1;
    valid[set][line_idx] = 1;
}

int get_max_time(int set) {
    int max = 0;
    int line_index = -1;
    for (int i = 0; i < LINE_COUNT / SET_COUNT; i++) {
        if (timer - time[set][i] >= max) {
            max = timer - time[set][i];
            line_index = i;
        }
    }
    return line_index;
}

int* read_line(int address) {
    int was_address = address;
    full++;
    timer++;
    int offset = address & ((1 << 5) - 1);
    address >>= 5;
    int set = address & ((1 << 4) - 1);
    address >>= 4;
    int tag = address & ((1 << 11) - 1);
    address = was_address;
    for (int i = 0; i < LINE_COUNT / SET_COUNT; i++) {
        if (line_tag[set][i] == tag && valid[set][i] == 1) {
            tacts += 6;
            cnt++;
            time[set][i] = timer;
            return data[set][i];
        }
    }
    tacts += 4;
    int start = address >> OFFSET << OFFSET;
    int line_index = get_max_time(set);
    if (dirty[set][line_index]) {
        push(set, line_index);
    }
    write_from_ram_to_line(set, line_index, start, tag);
    return data[set][line_index];
}

int read8(int address) {
    int* line = read_line(address);
    int offset = address & ((1 << OFFSET) - 1);
    return line[offset];
}

int read16(int address) {
    int* line = read_line(address);
    int offset = address & ((1 << OFFSET) - 1);
    return line[offset] | (line[offset + 1] << 8);
}

void write32(int address, int value) {
    int was_address = address;
    timer++;
    full++;
    int offset = address & ((1 << 5) - 1);
    address >>= 5;
    int set = address & ((1 << 4) - 1);
    address >>= 4;
    int tag = address & ((1 << 11) - 1);
    address = was_address;

    for (int i = 0; i < LINE_COUNT / SET_COUNT; i++) {
        if (line_tag[set][i] == tag) {
            tacts += 6;
            cnt++;
            data[set][i][offset] = value & ((1 << OFFSET) - 1);
            data[set][i][offset + 1] = (value >> 8) & ((1 << OFFSET) - 1);
            data[set][i][offset + 2] = (value >> 16) & ((1 << OFFSET) - 1);
            data[set][i][offset + 3] = (value >> 24) & ((1 << OFFSET) - 1);
            time[set][i] = timer;
            dirty[set][i] = 1;
            return;
        }
    }

    tacts += 4;
    mem[address] = value;
    int line_index = get_max_time(set);
    if (dirty[set][line_index])
        push(set, line_index);
    int start = address >> OFFSET << OFFSET;
    write_from_ram_to_line(set, line_index, start, tag);
}

void mmul()
{
    for (int i = 0; i < SET_COUNT; i++) {
        for (int j = 0; j < LINE_COUNT / SET_COUNT; j++) {
            valid[i][j] = 0;
            dirty[i][j] = 0;
            for (int k = 0; k < LINE_SIZE; k++) {
                data[i][j][k] = -1;
            }
        }
    }

    tacts += 7; // For initializating variables
    tacts += M * N * (K - 1) + M * (N - 1) + (M - 1); // for jump instructions
    tacts += M * N * K * 5; // for multiplication read8Result * read16Result
    tacts += M * N * K; // for pb += N * 2
    tacts += M * N * K * 2; // for pa + k and pb + x * 2
    tacts += M * N * K + M * N + M; // for k += 1, x += 1 and y += 1
    tacts += M * 2; // for pa += K and pc += N * 4

    int pa = 0;
    int pc = M * K + K * N * 2;
    for (int y = 0; y < M; y++)
    {
        for (int x = 0; x < N; x++)
        {
            int pb = M * K;
            int s = 0;
            for (int k = 0; k < K; k++)
            {
                int left = read8(pa + k);
                int right = read16(pb + x * 2);
                s += left * right;
                pb += N * 2;
            }
            write32(pc + x * 4, s);
        }
        pa += K;
        pc += N * 4;
    }

    printf("%d %d %.10f\n%d\n", cnt, full, (double)cnt/full, tacts);
}


signed main() {
    srand(23);
    for (int i = 0; i < M; i++) {
        for (int j = 0; j < K; j++) {
            mem[i * K + j] = rand() % 5;
            printf("%d ", mem[i * K + j]);
            fflush(stdout);
        }
        printf("\n");
    }
    printf("------\n");
    for (int i = 0; i < K; i++) {
        for (int j = 0; j < N * 2; j += 2) {
            mem[M * K + i * N * 2 + j] = rand() % 5;
            mem[M * K + i * N * 2 + j + 1] = 0;
            printf("%d ", mem[M * K + i * N * 2 + j + 1] << 8 | mem[M * K + i * N * 2 + j]);
            fflush(stdout);
        }
        printf("\n");
    }
    printf("------\n");
    mmul();
}
