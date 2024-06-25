typedef enum {C2_NOP,
              C2_READ_LINE,
              C2_WRITE_LINE,
              C2_RESPONSE, 
            C1_WRITE32,
              C1_WRITE16,
              C1_WRITE8,
              C1_INVALIDATE_LINE, 
              C1_READ32,
              C1_READ16,
              C1_READ8,
              C1_NOP,
              C1_RESPONSE
             } light_1;

module test();
  parameter ADDR1_BUS_SIZE = 15;
  parameter ADDR2_BUS_SIZE = 15;
  parameter DATA1_BUS_SIZE = 16;
  parameter DATA2_BUS_SIZE = 16;
  parameter CTR1_BUS_SIZE = 4;
  parameter CTR2_BUS_SIZE = 2;
  
  reg[DATA1_BUS_SIZE - 1:0] d1, d2;
  reg[ADDR1_BUS_SIZE - 1:0] a1, a2;
  reg[CTR1_BUS_SIZE - 1:0] c1;
  reg[CTR2_BUS_SIZE - 1:0] c2;
  reg[7:0] read8Result;
  reg[15:0] read16Result;
  reg[31:0] read32Result;
reg C_DUMP, M_DUMP, RESET, CLK = 0;
integer x, y, k, pa, pc, pb, s;
  parameter M = 64;
  parameter N = 60;
  parameter K = 32;
  
  integer forDebug = 0;
  real temp;
  
  always #1 begin
    CLK = ~CLK;
  end
  
  task read8(integer address);
    c1 = C1_READ8;
    a1 = address;
    #300 read8Result = d1;
  endtask
  
  task read16(integer address);
    c1 = C1_READ16;
    a1 = address;
    #300 read16Result = d1;
  endtask
  
  task read32(integer address);
    read8(address);
    read32Result = read8Result;
    read8(address + 1);
    read32Result |= read8Result << 8;
    read8(address + 2);
    read32Result |= read8Result << 16;
    read8(address + 3);
    read32Result |= read8Result << 24;
  endtask
  
  task write8(integer address, integer value);
    c1 = C1_WRITE8;
    a1 = address;
    d1 = value;
    #300;
  endtask
  
  task write32(integer address, integer value);
    c1 = C1_WRITE16;
    a1 = address;
    d1 = value & ((1 << 16) - 1);
    #300;
    c1 = C1_WRITE16;
    a1 += 2;
    d1 = (value >> 16) & ((1 << 16) - 1);
    #300;
    Cache.full--;
    Cache.hits--;
    Cache.tacts -= 6;
  endtask
  
  integer ii, jj, res;
  
  initial begin
    c1 = C1_NOP;
    c2 = C2_NOP;
    #1 RESET = 0;
    #1 RESET = 1;
    
    // #100;
    // for (ii = 0; ii < M; ii += 1) begin
    //   for (jj = 0; jj < K; jj += 1) begin
    //     $write("[%d, %d]", MemCTR.mem[ii * K + jj], ii * K + jj);
    //   end
    //   $write("\n");
    // end
    // $display("-----------");
    
    // #100;
    // for (ii = 0; ii < K; ii += 1) begin
    //   for (jj = 0; jj < N * 2; jj += 2) begin
    //     res = MemCTR.mem[M * K + ii * N * 2 + jj] | (MemCTR.mem[M * K + ii * N * 2 + jj + 1] << 8);
    //     $write("[%d, %d]",res, M * K + ii * N * 2 + jj);
    //   end
    //   $write("\n");
    // end
    // $display("-----------");
    
    Cache.tacts += 7; // For initializating variables
    Cache.tacts += M * N * (K - 1) + M * (N - 1) + (M - 1); // for jump instructions
    Cache.tacts += M * N * K * 5; // for multiplication read8Result * read16Result
    Cache.tacts += M * N * K; // for pb += N * 2
    Cache.tacts += M * N * K * 2; // for pa + k and pb + x * 2
    Cache.tacts += M * N * K + M * N + M; // for k += 1, x += 1 and y += 1
    Cache.tacts += M * 2; // for pa += K and pc += N * 4

    pa = 0;
    pc = M * K + K * N * 2;
    for (y = 0; y < M; y += 1) begin
      $write("Processing %d row\n", y);
      for (x = 0; x < N; x += 1) begin
        pb = M * K;
        s = 0;
        for (k = 0; k < K; k += 1) begin
          read8(pa + k);
          read16(pb + x * 2);
          s += read8Result * read16Result;
          pb += N * 2;
        end
        write32(pc + x * 4, s);
      end
      pa += K;
      pc += N * 4;
    end
    
    temp = Cache.hits;
    #100 $display("%d %d %f %d", Cache.hits, Cache.full, temp / Cache.full, Cache.tacts);
    $finish;
  end
  
  
endmodule



module CPU();
  always @(posedge test.CLK) begin
    case(test.c1)
      C1_RESPONSE: begin
        //$display("address = %d, value = %d", test.a1, test.d1);
        test.c1 = C1_NOP;
      end
    endcase
  end

endmodule

module Cache();
  reg isHit = 0;
  
  parameter CACHE_SIZE = 1024;
  parameter CACHE_LINE_SIZE = 32;
  parameter CACHE_LINE_COUNT = 32;
  parameter CACHE_SET_COUNT = 16;
  parameter CACHE_WAY = 2;
  
  parameter CACHE_ADDR_SIZE = 20;
  parameter CACHE_SET_SIZE = 4;
  parameter CACHE_OFFSET_SIZE = 5;
  parameter CACHE_TAG_SIZE = 20 - CACHE_SET_SIZE - CACHE_OFFSET_SIZE;
  
  reg[7:0] data[0:CACHE_SET_COUNT - 1][CACHE_WAY][CACHE_LINE_SIZE];
  reg[CACHE_TAG_SIZE - 1:0] lineTag[0:CACHE_SET_COUNT - 1][CACHE_WAY];
  reg valid[0:CACHE_SET_COUNT - 1][CACHE_WAY];
  reg dirty[0:CACHE_SET_COUNT - 1][CACHE_WAY];
  integer lastModify[0:CACHE_SET_COUNT - 1][CACHE_WAY];
  
  integer timer = 0;
  integer full = 0;
  integer hits = 0;
  integer tacts = 0;
  
  integer getMaxLineResult;
  
  integer setResponse, lineResponse, indexResponse;
  
  integer i, lineIndex;
  reg[CACHE_TAG_SIZE - 1:0] tag;
  reg[CACHE_SET_SIZE - 1:0] set;
  reg[CACHE_OFFSET_SIZE - 1:0] offset;
  reg flag;
  
  task push(integer whichSet, integer whichLine);
    for (i = 0; i < CACHE_LINE_SIZE; i++) begin
      MemCTR.mem[data[whichSet][whichLine][i] >> (CACHE_OFFSET_SIZE + CACHE_SET_SIZE) << (CACHE_OFFSET_SIZE + CACHE_SET_SIZE) | (whichSet << CACHE_OFFSET_SIZE) | i] = data[whichSet][whichLine][i];
    end
  endtask
  
  integer min;
  task getMaxLine(integer set);
    min = 0;
    for (i = 0; i < CACHE_WAY; i += 1) begin
      if (timer - lastModify[set][i] >= min) begin
        min = timer - lastModify[set][i];
        getMaxLineResult = i;
      end
    end
  endtask
  
  task read_byte1(integer address);
    timer++;
    isHit = 0;
    
    offset = address & ((1 << CACHE_OFFSET_SIZE) - 1);
    set = ((address >> CACHE_OFFSET_SIZE) & ((1 << CACHE_SET_SIZE) - 1));
    tag = address >> (CACHE_OFFSET_SIZE + CACHE_SET_SIZE);
    
    for (i = 0; i < CACHE_WAY; i += 1) begin
      if (lineTag[set][i] == tag && valid[set][i] == 1) begin
        isHit = 1;
        lastModify[set][i] = timer;
        test.d1 = data[set][i][offset];
        test.c1 = C1_RESPONSE;
       end
    end
  endtask
  
  task read_byte2(integer address);
    timer++;
    isHit = 0;
    
    offset = address & ((1 << CACHE_OFFSET_SIZE) - 1);
    set = ((address >> CACHE_OFFSET_SIZE) & ((1 << CACHE_SET_SIZE) - 1));
    tag = address >> (CACHE_OFFSET_SIZE + CACHE_SET_SIZE);
    
    for (i = 0; i < CACHE_WAY; i += 1) begin
      if (lineTag[set][i] == tag && valid[set][i] == 1) begin
        isHit = 1;
        lastModify[set][i] = timer;
        test.d1 = data[set][i][offset] | (data[set][i][offset + 1] << 8);
        test.c1 = C1_RESPONSE;
       end
    end
  endtask
  
  task read_cache_line(integer address);
    timer++;
    
    offset = address & ((1 << CACHE_OFFSET_SIZE) - 1);
    set = ((address >> CACHE_OFFSET_SIZE) & ((1 << CACHE_SET_SIZE) - 1));
    tag = address >> (CACHE_OFFSET_SIZE + CACHE_SET_SIZE);
    
    getMaxLine(set);
    
    setResponse = set;
    lineResponse = getMaxLineResult;
    indexResponse = 0;
    
    lineTag[set][lineResponse] = tag;
    valid[set][lineResponse] = 1;
    dirty[set][lineResponse] = 0;
    lastModify[set][lineResponse] = timer;
    
    test.c2 = C2_READ_LINE;
    test.a2 = test.a1 >> CACHE_OFFSET_SIZE;
    test.c1 = C1_NOP;
  endtask
  
  task write_byte(integer address, integer value);
    isHit = 0;
    timer++;
    
    offset = address & ((1 << CACHE_OFFSET_SIZE) - 1);
    set = ((address >> CACHE_OFFSET_SIZE) & ((1 << CACHE_SET_SIZE) - 1));
    tag = address >> (CACHE_OFFSET_SIZE + CACHE_SET_SIZE);
    
        for (i = 0; i < CACHE_WAY; i += 1) begin
          if (lineTag[set][i] == tag) begin
            isHit = 1;
            data[set][i][offset] = value;
            lastModify[set][i] = timer;
            dirty[set][i] = 1;
            test.c1 = C1_NOP;
          end
        end
        
        if (isHit == 0) begin
          MemCTR.mem[address] = value;

          getMaxLine(set);
          lineResponse = getMaxLineResult;

          if (dirty[set][lineResponse] == 1) begin
            push(set, lineResponse);
          end
          
          setResponse = set;
          indexResponse = 0;

          lineTag[set][lineResponse] = tag;
          valid[set][lineResponse] = 1;
          dirty[set][lineResponse] = 1;
          lastModify[set][lineResponse] = timer;

          test.c2 = C2_READ_LINE;
          test.a2 = address >> CACHE_OFFSET_SIZE;
          test.c1 = C1_NOP;
        end
  endtask
  
  always @(posedge test.CLK) begin
    case (test.c2) 
      C2_RESPONSE: begin
        
        data[setResponse][lineResponse][indexResponse] = test.d2 & ((1 << 8) - 1);
        data[setResponse][lineResponse][indexResponse + 1] = (test.d2 >> 8) & ((1 << 8) - 1);
        
        indexResponse += 2;
        
        if (indexResponse == CACHE_LINE_SIZE) begin
          indexResponse = 0;
          test.c2 = C2_NOP;
        end
      end
    endcase
  end
  
  always @(posedge test.CLK) begin
    case(test.c1)
      C1_READ8: begin
        full++;
        read_byte1(test.a1);
        if (isHit == 0) begin
          read_cache_line(test.a1);
          #200 read_byte1(test.a1);
          tacts += 104;
        end
        else begin
          hits++;
          tacts += 6;
        end
      end
      C1_READ16: begin
        full++;
        read_byte2(test.a1);
        if (isHit == 0) begin
          read_cache_line(test.a1);
          #200 read_byte2(test.a1);
          tacts += 104;
        end
        else begin
          hits++;
          tacts += 6;
        end
      end
      C1_READ32: begin
        // No realisation, because d1 is only 16 bit, so No reason to use this Command
      end
      C1_INVALIDATE_LINE: begin
        offset = test.a1 & ((1 << CACHE_OFFSET_SIZE) - 1);
        set = ((test.a1 >> CACHE_OFFSET_SIZE) & ((1 << CACHE_SET_SIZE) - 1));
    tag = test.a1 >> (CACHE_OFFSET_SIZE + CACHE_SET_SIZE);
        
        for (i = 0; i < CACHE_WAY; i += 1) begin
          if (lineTag[set][i][offset] == tag) begin
            valid[set][i] = 0;
          end
        end
      end
      C1_WRITE8: begin
        full++;
        write_byte(test.a1, test.d1);
        if (isHit == 1) begin
          tacts += 6;
          hits++;
        end
        else begin
          tacts += 104;
        end
      end
      C1_WRITE16: begin
        full++;
        write_byte(test.a1, test.d1 & ((1 << 8) - 1));
        if (isHit == 1) begin
          hits++;
          tacts += 6;
        end
        else begin
          tacts += 104;
        end
        write_byte(test.a1 + 1, (test.d1 >> 8) & ((1 << 8) - 1));
      end
      C1_WRITE32: begin
        // No realisation, because d1 is only 16 bit, so No reason to use this Command
      end
    endcase
  end
  
  always @(posedge test.C_DUMP) begin
    integer setIndex, lineIndex, offset;
    for (setIndex = 0; setIndex < CACHE_SET_COUNT; setIndex += 1) begin
      $display("Set %d:", setIndex);
      for (lineIndex = 0; lineIndex < CACHE_WAY; lineIndex += 1) begin
        $display("  Cache_line %d:", lineIndex);
        for (offset = 0; offset < CACHE_LINE_SIZE; offset += 1) begin
          $display("    %d", offset);
        end
      end
    end
  end
  
  always @(posedge test.RESET) begin
    integer setIndex, lineIndex;
    for (setIndex = 0; setIndex < CACHE_SET_COUNT; setIndex += 1) begin
      for (lineIndex = 0; lineIndex < CACHE_WAY; lineIndex += 1) begin
        valid[setIndex][lineIndex] = 0;
        dirty[setIndex][lineIndex] = 0;
        lastModify[setIndex][lineIndex] = 0;
      end
    end
  end
endmodule

module MemCTR();
  parameter MEM_SIZE = 1 << 20;
  reg[7:0] mem[0:MEM_SIZE - 1];
  
  integer passedRead = 0;
  integer passedWrite = 0;
  
  integer start, i;
  
  always @(posedge test.CLK) begin
    if (test.c2 == C2_WRITE_LINE) begin
      mem[test.a2 + passedWrite] = test.d2 & ((1 << 8) - 1);
      mem[test.a2 + passedWrite + 1] = (test.d2 >> 8) & ((1 << 8) - 1);
      passedWrite += 2;
      if (passedWrite == Cache.CACHE_LINE_SIZE / test.DATA2_BUS_SIZE) begin
        passedWrite = 0;
      end
    end
    else if (test.c2 == C2_READ_LINE) begin
      start = test.a2 << Cache.CACHE_OFFSET_SIZE;
      for (i = start; i < Cache.CACHE_LINE_SIZE + start; i += 2) begin
        test.d2 = mem[i] | (mem[i + 1] << 8);
        test.c2 = C2_RESPONSE;
        @(negedge test.CLK);
      end
    end
  end
  
  always @(posedge test.M_DUMP) begin
    for (i = 0; i < MEM_SIZE; i += 1) begin
      $display("[%d] %d", i, mem[i]);  
    end
  end
  
  integer SEED = 225526;
  always @(posedge test.RESET) begin
    for (i = 0; i < MEM_SIZE; i += 1) begin
      mem[i] = $random(SEED)>>16;  
    end
  end
  
endmodule