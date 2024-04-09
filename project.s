#######################
#
# Filename: project.s
#
# Author: Stephen Henstrom
# Class: ECEn 323, Section 002, Winter 2024
# Date: 4/3/2024
#
# This is an implementation of Snake in assembly on the Artix-7 FPGA board
#
# Memory Organization:
#   0x0000-0x1fff : text
#   0x2000-0x3fff : data
#   0x7f00-0x7fff : I/O
#   0x8000-0xbfff : VGA
# Registers:
#   x0: Zero
#   x1: return address
#   x2 (sp): stack pointer (starts at 0x3ffc)
#   x3 (gp): global pointer (to data: 0x2000)
#   x10-x11: function arguments/return values
#
# Functions:
#	- main
#######################

.globl  main

.data
     .word 0

.text


# I/O address offset constants
    .eqv LED_OFFSET 0x0
    .eqv SWITCH_OFFSET 0x4
    .eqv SEVENSEG_OFFSET 0x18
    .eqv BUTTON_OFFSET 0x24
    .eqv CHAR_COLOR_OFFSET 0x34
    .eqv TIMER 0x30

# I/O mask constants
    .eqv BUTTON_C_MASK 0x01
    .eqv BUTTON_L_MASK 0x02
    .eqv BUTTON_D_MASK 0x04
    .eqv BUTTON_R_MASK 0x08
    .eqv BUTTON_U_MASK 0x10

# Game specific constants
    .eqv CHAR_MONKEY 0x000fff06          # Modified ASCII character that is our monkey with black background and green foreground
    .eqv CHAR_BANANA 0x000ff005         # Modified ASCII character that is our banana with black background and yellow foreground
    .eqv CHAR_G_RED 0x000f0047		# Modified ASCII 'G' with black background and red foreground
    .eqv CHAR_A_RED 0x000f0047		# Modified ASCII 'A' with black background and red foreground
    .eqv CHAR_M_RED 0x000f0047		# Modified ASCII 'M' with black background and red foreground
    .eqv CHAR_E_RED 0x000f0047		# Modified ASCII 'E' with black background and red foreground
    .eqv CHAR_O_RED 0x000f0047		# Modified ASCII 'O' with black background and red foreground
    .eqv CHAR_V_RED 0x000f0047		# Modified ASCII 'V' with black background and red foreground
    .eqv CHAR_R_RED 0x000f0047		# Modified ASCII 'R' with black background and red foreground
    .eqv CHAR_SPACE 0x000f0020          # Modified ASCII ' ' with black background and red foreground
    .eqv COLUMN_MASK 0x1fc              # Mask for the bits in the VGA address for the column
    .eqv COLUMN_SHIFT 2                 # Number of right shifts to determine VGA column
    .eqv ROW_MASK 0x3e00                # Mask for the bits in the VGA address for the row
    .eqv ROW_SHIFT 9                    # Number of right shifts to determine VGA row
    .eqv FIRST_COLUMN 8                 # 8 - monkey can't go past this column
    .eqv FIRST_ROW 4                    # 4 - monkey can't go past this row
    .eqv LAST_COLUMN 64                 # 64 - monkey can't go past this column
    .eqv LAST_ROW 25                    # 25 - monkey can't go past this row
    .eqv INIT_ROW_LOC 14
    .eqv INIT_COL_LOC 38
    .eqv ARRAY_OFFSET 0x4               
    .eqv ADDRESSES_PER_ROW 512
    .eqv NEG_ADDRESSES_PER_ROW -512
    .eqv STARTING_LOC 0x8204            # The VGA memory address wher ethe 'starting' character is located.
                                        # 1,2 or 0x8000+1*4+2*512=0x8204
    .eqv ENDING_LOC 0xb700              # The VGA memory address where the 'ending character' is located
                                        # 64, 27 or 0x8000+64*4+27*512=0xb700
    .eqv BLOCK_LOC 0x987C               # The VGA memory address where the 'block character' is located
                                        # 31, 12 or 0x8000+31*4+12*512=0x987C
    .eqv SEGMENT_TIMER_INTERVAL 100     # This constant represents the number of timer ticks (each 1 ms)
                                        # that are needed before incrementing the timer value on the seven
                                        # segment display. With a value of 100, the timer will increment
                                        # every 250 ms (or 4 times a second).

    .eqv INIT_FASTEST_SCORE 0xffff      # Fastest score initialized to 0xffff (should get lower with better play)
    .eqv ROW_AND_RANDOM_MASK 0x0000001f
    .eqv ROW_OR_RANDOM_MASK 0x00000004
    .eqv ROW_SUBTRACT_CONST -7
    .eqv COL_AND_RANDOM_MASK 0x0000002f
    .eqv COL_OR_RANDOM_MASK 0x00000008

main:
     # The purpose of this initial section is to setup the global registers that
    # will be used for the entire program execution. This setup portion will only
    # be run once.

    # Setup the stack pointer: sp = 0x3ffc
    li sp, 0x3ffc
    # The previous "pseudo instruction" will be compiled into the following two instructions:
    #  lui sp, 4		# 4 << 12 = 0x4000
    #  addi sp, sp, -4		# 0x4000 - 4 = 0x3ffc

    # setup the global pointer to the data segment (2<<12 = 0x2000)
    lui gp, 2

    # Prepare I/O base address
    li tp, 0x7f00
    
    #init timer
    sw x0, TIMER(tp)
 
    # Prepare VGA base address
    li s0, 0x8000
    
    #initialize pointer to array of snake locations in data memory
    add s1, gp, x0
    
    #initialize counter of how many items are in array s1
    addi s2, x0, 0
    
    #intialize seven segment display with all 0s
    sw x0, SEVENSEG_OFFSET(tp)
    
    #intialize leds
    sw x0 LED_OFFSET(tp)
    
GENERATE_INITIAL_BANANA:

    #clear all temporary registers
    xor t0, t0, t0
    xor t1, t1, t1
    xor t2, t2, t2
    xor t3, t3, t3
    xor t4, t4, t4
    xor t5, t5, t5
    xor t6, t6, t6

    # Generate random row and column for apple location
    li t3, 0x8000  # Starting address of VGA memory

    # Load the address of GENERATE_RANDOM_ROW into a register
    lui t0, %hi(GENERATE_RANDOM_ROW)
    addi t0, t0, %lo(GENERATE_RANDOM_ROW)

    # Jump to GENERATE_RANDOM_ROW using jalr
    jalr ra, t0, 0              # ra is the return address
    add t1, x0, a0              # Store random row in t1
    slli t1, t1, ROW_SHIFT      # Shift row to correct location in VGA memory
    add t3, t3, t1              # Add row to VGA memory address

    # Generate random column
    xor t0, t0, t0              # Clear t0
    lui t0, %hi(GENERATE_RANDOM_COLUMN) # Load the address of GENERATE_RANDOM_COLUMN into a register
    addi t0, t0, %lo(GENERATE_RANDOM_COLUMN) # Add the offset of GENERATE_RANDOM_COLUMN to the address

    jalr ra, t0, 0              # ra is the return address
    add t1, x0, a0              # Store random column in t1
    slli t1, t1, COLUMN_SHIFT   # Shift column to correct location in VGA memory
    add t3, t3, t1              # Add column to VGA memory address

    # Store banana VGA Location in s3
    add s3, x0, t3

INITIALIZE_MONKEY_LOC:
    #initialize the first location of the monkey
    #This puts the offsets for the row and the column for the initial vga location
    #into t1 and t0 respectively
    addi t0, x0, INIT_COL_LOC
    addi t1, x0, INIT_ROW_LOC
    add s4, t1, x0 # s4 STORES THE ROW OF THE MONKEY
    add s5, t0, x0 # s5 STORES THE COL OF THE MONKEY
    slli t0, t0, COLUMN_SHIFT
    slli t1, t1, ROW_SHIFT
    
    # put the inital VGA location of MONKEY t2 
    add t2, s0, x0
    add t2, t2, t1
    add t2, t2, t0
    
    # Now store the word in the offset of our
    sw t2, 0(s1)            # store the VGA location of the monkey

    # Call main program procedure
    jal INIT_MONKEY

    # End in infinite loop (should never get here)
END_MAIN:
    j END_MAIN

GENERATE_RANDOM_ROW:
    # Generate a random number between 4 and 25ROW_SUBTRACT_CONST
    xor t0, t0, t0 #clear t0
    lw t0, TIMER(tp) #load timer value into temp register t0
    andi t0, t0, ROW_AND_RANDOM_MASK #MAKE SURE VALUE IS LESS THAN 32
    ori t0, t0, ROW_OR_RANDOM_MASK #MAKE SURE VALUE IS GREATER THAN 4
    addi t1, x0, LAST_ROW
    bge t1, t0 SKIP
    addi t0, t0, ROW_SUBTRACT_CONST
SKIP:
    add a0, t0, x0
    ret
    

GENERATE_RANDOM_COLUMN:
    # Generate a random number between 4 and 64
    xor t0, t0, t0
    lw t0, TIMER(tp) #load timer value into temp register t0
    andi t0, t0, COL_AND_RANDOM_MASK #make sure value is less than 64
    ori t0, t0, COL_OR_RANDOM_MASK  #make sure value is greater than 8
    add a0, t0, x0
    ret
    

INIT_MONKEY:
    lw t0, 0(s1) #get VGA address of monkey
    li t1, CHAR_MONKEY #load into temp register monkey char value
    sw t1, 0(t0) #load snake char value into VGA address of monkey
    
NO_BUTTON_START:
    lw t0, BUTTON_OFFSET(tp)
    bne t0, x0, NO_BUTTON_START
    
BUTTON_START:
    lw t0, BUTTON_OFFSET(tp)
    beq t0, x0, BUTTON_START
     
    #a button has been pressed to start the game
    #copy button values to a0
    mv a0, t0
    
    #Clear seven segment display and LEDs and Timer
    sw x0, SEVENSEG_OFFSET(tp)
    sw x0, LED_OFFSET(tp)
    sw x0, TIMER(tp)      

PROC_BUTTONS:
    #see if btnc is pressed (to reset game)
    li t0, BUTTON_C_MASK
    beq t0, a0, INIT_MONKEY #if the center button is pressed, go back to init monkey screen
    
    #Continue the game
    jal UPDATE_CHAR_ADDRESS
    
    #jal move char
    jal MOVE_CHAR
    
    beq s3, a0, ADD_POINT
    

CONTINUE:
    #Wait for button release while updating timer
    jal UPDATE_TIMER
    lw t0, BUTTON_OFFSET(tp)
    beq x0, t0, CONTINUE
    mv a0, t0 #copy button value to a0
    j PROC_BUTTONS

UPDATE_CHAR_ADDRESS:
    

MOVE_CHAR:



UPDATE_TIMER:
    lw t0, TIMER(tp) #load timer value
    li t1, SEGMENT_TIMER_INTERVAL #load constant
    bne t1, t0, DONE
    
    #clear timer by writing a 0 to it
    sw x0, TIMER(tp)
    #Load the current value being displayed on seven segment display
    lw t0, SEVENSEG_OFFSET(tp)
    #add 1 to that value
    addi t0, t0, 1
    #update display
    sw t0, SEVENSEG_OFFSET(tp)
    
DONE:
    lw a0, SEVENSEG_OFFSET(tp)
    ret
    
    
