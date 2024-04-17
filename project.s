
#######################
#
# Filename: project.s
#
# Author: Stephen Henstrom, Matthew Topham
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
    .eqv CHAR_A_RED 0x000f0041		# Modified ASCII 'A' with black background and red foreground
    .eqv CHAR_M_RED 0x000f004d		# Modified ASCII 'M' with black background and red foreground
    .eqv CHAR_E_RED 0x000f0045		# Modified ASCII 'E' with black background and red foreground
    .eqv CHAR_O_RED 0x000f004f		# Modified ASCII 'O' with black background and red foreground
    .eqv CHAR_V_RED 0x000f0056		# Modified ASCII 'V' with black background and red foreground
    .eqv CHAR_R_RED 0x000f0052		# Modified ASCII 'R' with black background and red foreground
    .eqv CHAR_SPACE 0x00000020          # Modified ASCII ' ' with black background
    .eqv COLUMN_MASK 0x1fc              # Mask for the bits in the VGA address for the column
    .eqv COLUMN_SHIFT 2                 # Number of right shifts to determine VGA column
    .eqv ROW_MASK 0x3e00                # Mask for the bits in the VGA address for the row
    .eqv ROW_SHIFT 9                    # Number of right shifts to determine VGA row
    .eqv FIRST_COLUMN 8                 # 8 - monkey can't go past this column
    .eqv FIRST_ROW 4                    # 4 - monkey can't go past this row
    .eqv LAST_COLUMN 64                 # 64 - monkey can't go past this column
    .eqv LAST_ROW 25                    # 25 - monkey can't go past this row
    .eqv INIT_ROW_LOC 14                # Initial row location of the monkey
    .eqv INIT_COL_LOC 38                # Initial column location of the monkey
    .eqv INIT_BANANA_ROW 13             # Initial row location of the banana
    .eqv INIT_BANANA_COL 38             # Initial column location of the banana
    .eqv ADDRESSES_PER_ROW 512          # Number of addresses per row in VGA memory
    .eqv NEG_ADDRESSES_PER_ROW -512     # Negative number of addresses per row in VGA memory
    .eqv STARTING_LOC 0x987C            # The VGA memory address wher ethe 'starting' character is located.
                                        # 1,2 or 0x8000+1*4+2*512=0x8204
    .eqv G_ADDRESS 0x987C               # The VGA memory address where the 'G' character is located
    .eqv A_ADDRESS 0x9880               # The VGA memory address where the 'A' character is located
    .eqv M_ADDRESS 0x9884               # The VGA memory address where the 'M' character is located
    .eqv E_ADDRESS 0x9888               # The VGA memory address where the 'E' character is located
    .eqv SPACE_ADDRESS 0x988C           # The VGA memory address where the 'space' character is located
    .eqv O_ADDRESS 0x9890               # The VGA memory address where the 'O' character is located
    .eqv V_ADDRESS 0x9894               # The VGA memory address where the 'V' character is located
    .eqv EE_ADDRESS 0x9898              # The VGA memory address where the second 'E' character is located
    .eqv R_ADDRESS 0x989C               # The VGA memory address where the 'R' character is located
    
    .eqv ENDING_LOC 0xb700              # The VGA memory address where the 'ending character' is located
                                        # 64, 27 or 0x8000+64*4+27*512=0xb700
    .eqv BANANA_LOC 0x9880               # The VGA memory address where the 'block character' is located
                                        # 31, 12 or 0x8000+31*4+12*512=0x987C
    .eqv SEGMENT_TIMER_INTERVAL 1000     # This constant represents the number of timer ticks (each 1 ms)
                                        # that are needed before incrementing the timer value on the seven
                                        # segment display. With a value of 100, the timer will increment
                                        # every 250 ms (or 4 times a second).

    .eqv INIT_FASTEST_SCORE 0xffff      # Fastest score initialized to 0xffff (should get lower with better play)
    .eqv ROW_AND_RANDOM_MASK 0x0000001f # Mask to ensure random row is less than 32
    .eqv ROW_OR_RANDOM_MASK 0x00000004 # Mask to ensure random row is greater than 4
    .eqv ROW_SUBTRACT_CONST -7          # Constant to subtract from random row to get value between 4 and 25
    .eqv COL_AND_RANDOM_MASK 0x0000002f # Mask to ensure random column is less than 64
    .eqv COL_OR_RANDOM_MASK 0x00000008 # Mask to ensure random column is greater than 8
    .eqv MAX_TIME 0x00000020            # Maximum time allowed for the game (32 in decimal)

# The purpose of this initial section is to setup the global registers that
# will be used for the entire program execution. This setup portion will only
# be run once.
main:
    # Setup the stack pointer: sp = 0x3ffc
    li sp, 0x3ffc

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
    
    #initialize counter for bananas
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

    
    # Store banana VGA Location in s3
    li s3, BANANA_LOC       # Store the VGA location of the banana
    li t4, CHAR_BANANA      # Store the character for the banana
    sw t4, 0(s3)            # Store the character in the VGA memory

INITIALIZE_MONKEY_LOC:
    # Call main program procedure
    jal INIT_MONKEY

GENERATE_RANDOM_ROW:
    # Generate a random number between 4 and 25ROW_SUBTRACT_CONST
    xor t0, t0, t0 #clear t0
    lw t0, TIMER(tp)                 #load timer value into temp register t0
    andi t0, t0, ROW_AND_RANDOM_MASK #MAKE SURE VALUE IS LESS THAN 32
    ori t0, t0, ROW_OR_RANDOM_MASK #MAKE SURE VALUE IS GREATER THAN 4
    addi t1, x0, LAST_ROW          #load last row value into t1
    bge t1, t0 SKIP                #if last row is greater than random row, skip 
    addi t0, t0, ROW_SUBTRACT_CONST #subtract 7 from random row

SKIP:
    add a1, t0, x0 #store random row in a1
    ret            #return with random row in a1 
    

GENERATE_RANDOM_COLUMN:
    # Generate a random number between 4 and 64
    xor t0, t0, t0
    lw t0, TIMER(tp) #load timer value into temp register t0
    andi t0, t0, COL_AND_RANDOM_MASK #make sure value is less than 64
    ori t0, t0, COL_OR_RANDOM_MASK  #make sure value is greater than 8
    add a1, t0, x0
    ret
    

INIT_MONKEY:
    li t0, STARTING_LOC #get VGA address of monkey
    lw t1, 0(t0)
    srli t1, t1, 8
    sw t1, CHAR_COLOR_OFFSET(tp) #writes new color value

    
RESTART:
    #clear GAME OVER
    li t0, G_ADDRESS
    li t1, CHAR_SPACE
    sw t1, 0(t0)
    li t0, A_ADDRESS
    sw t1, 0(t0)
    li t0, M_ADDRESS
    sw t1, 0(t0)
    li t0, E_ADDRESS
    sw t1, 0(t0)
    li t0, O_ADDRESS
    sw t1, 0(t0)
    li t0, V_ADDRESS
    sw t1, 0(t0)
    li t0, EE_ADDRESS
    sw t1, 0(t0)
    li t0, R_ADDRESS
    sw t1, 0(t0)
    
    li a0, STARTING_LOC #place the monkey in starting location
    li t0, CHAR_SPACE #load space character
    sw t0, 0(s3) #erase old banana
    add t3, x0, s0  # Starting address of VGA memory
    lw t1, 0(t0)
    srli t1, t1, 8
    sw t1, CHAR_COLOR_OFFSET(tp) #writes new color value
    add s2, x0, x0 		#reset counter register
    jal MOVE_CHAR 
    li s3, BANANA_LOC	# Store banana VGA Location in s3
    li t1, CHAR_BANANA
    sw t1, 0(s3)
    
    #Clear seven segment display and LEDs and Timer
    sw x0, SEVENSEG_OFFSET(tp)
    sw x0, LED_OFFSET(tp)
    sw x0, TIMER(tp)      

    
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
    beq t0, a0, RESTART #if the center button is pressed, go back to init monkey screen
    
    #Continue the game
    jal UPDATE_CHAR_ADDRESS
    
    #jal move char
    jal MOVE_CHAR
    
    #if monkey is on banana branch to add point
    beq s3, a0, ADD_POINT
    

CONTINUE:
    #Wait for button release while updating timer
    jal UPDATE_TIMER
    lw t0, BUTTON_OFFSET(tp)
    bne x0, t0, CONTINUE
    
CONTINUE_BTN:
    jal UPDATE_TIMER
    lw t0, BUTTON_OFFSET(tp)
    beq x0, t0, CONTINUE_BTN
    mv a0, t0 #copy button value to a0
    j PROC_BUTTONS
    
ADD_POINT:
    addi s2, s2, 1 #add a point to the counter
    sw s2, LED_OFFSET(tp)
    jal GENERATE_RANDOM_ROW
    add t0, a1, x0 		#store random row in t0
    slli t0, t0, ROW_SHIFT 	#Shift column to correct location
    add t3, x0, s0
    add t3, t3, t0		#Add row to VGA memory address
    jal GENERATE_RANDOM_COLUMN
    add t1, x0, a1              # Store random column in t1
    slli t1, t1, COLUMN_SHIFT   # Shift column to correct location in VGA memory
    add t3, t3, t1              # Add column to VGA memory address

    # Store banana VGA Location in s3
    add s3, x0, t3
    li t4, CHAR_BANANA
    sw t4, 0(s3)
    j CONTINUE

END_GAME:
    #display GAME OVER
    li t0, G_ADDRESS
    li t1, CHAR_G_RED
    sw t1, 0(t0)
    li t0, A_ADDRESS
    li t1, CHAR_A_RED
    sw t1, 0(t0)
    li t0, M_ADDRESS
    li t1, CHAR_M_RED
    sw t1, 0(t0)
    li t0, E_ADDRESS
    li t1, CHAR_E_RED
    sw t1, 0(t0)
    li t0, SPACE_ADDRESS
    li t1, CHAR_SPACE
    sw t1, 0(t0)
    li t0, O_ADDRESS
    li t1, CHAR_O_RED
    sw t1, 0(t0)
    li t0, V_ADDRESS
    li t1, CHAR_V_RED
    sw t1, 0(t0)
    li t0, EE_ADDRESS
    li t1, CHAR_E_RED
    sw t1, 0(t0)
    li t0, R_ADDRESS
    li t1, CHAR_R_RED
    sw t1, 0(t0)
    j WAIT


UPDATE_CHAR_ADDRESS:
    addi sp, sp, -4 #make room and save RA on stack
    sw ra, 0(sp) #put return address on stack
    # load current character address into t2
    lw t2, %lo(DISPLACED_CHAR_LOC)(gp)
    # compute current column and row
    li t0, COLUMN_MASK
    and t3, t0, t2
    srli t3, t3, COLUMN_SHIFT
    li t0, ROW_MASK
    and t4, t0, t2
    srli t4, t4, ROW_SHIFT
    
CHECK_BTNR:
    li t0, BUTTON_R_MASK
    bne t0, a0, CHECK_BTNL
    li t1, LAST_COLUMN
    beq t3, t1, CHECKER_DONE #if last column do nothing
    addi t2, t2, 4 #increment pointer
    j CHECKER_DONE
    
CHECK_BTNL:
    li t0, BUTTON_L_MASK
    bne t0, a0, CHECK_BTND
    li t1, FIRST_COLUMN
    beq t3, t1, CHECKER_DONE #if first column do nothing
    addi t2, t2, -4 #decrement pointer
    j CHECKER_DONE
    
CHECK_BTND:
    li t0, BUTTON_D_MASK
    bne t0, a0, CHECK_BTNU
    li t1, LAST_ROW
    beq t4, t1, CHECKER_DONE #if in last row do nothing
    addi t2, t2, ADDRESSES_PER_ROW #increment pointer
    j CHECKER_DONE
    
CHECK_BTNU:
    li t0, BUTTON_U_MASK
    bne t0, a0, CHECKER_DONE
    li t1, FIRST_ROW
    beq t4, t1, CHECKER_DONE #if in first row do nothing
    addi t2, t2, NEG_ADDRESSES_PER_ROW #decrement pointer
    
CHECKER_DONE:
    #load the character at the new location
    lw t0, 0(t2)
    
CHECKER_RET:
    mv a0, t2
    lw ra, 0(sp) #restore return address
    addi sp, sp, 4 #update stack pointer
    ret

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
    #load max time into t1
    li t1, MAX_TIME
    bge t0, t1, END_GAME #if time is greater than alotted time end game
    
DONE:
    lw a0, SEVENSEG_OFFSET(tp)
    ret
    
MOVE_CHAR:
    addi sp, sp, -4 #make room and save RA on stack
    sw ra, 0(sp) #put return address on stack
    
    #load the address of the old character that was previously replaced
    lw t3, %lo(DISPLACED_CHAR_LOC)(gp)
    #if this address is zero, no need to restore charcter
    beq t3, x0, SAVE_DISPLACED_CHAR
    
    #load the value of the chracter that was previously displaced
    lw t2, %lo(DISPLACED_CHAR)(gp)
    #restore the character that was displaced
    sw t2, 0(t3)
    #load character space into t2
    li t2, CHAR_SPACE
    #erase the previous banana
    sw t2, 0(t3)
    
SAVE_DISPLACED_CHAR:
    #load value of the character that is going to be displaced
    lw t1, 0(a0)
    #load address of the displaced character location
    addi t0, gp, %lo(DISPLACED_CHAR)
    #save the value of the displaced character
    sw t1, 0(t0)
    #save the address of the displaced character
    addi t0, gp, %lo(DISPLACED_CHAR_LOC)
    sw a0, 0(t0)
    
UPDATE_MOVING_CHAR:
    #load the chracter value to write into the new location
    lw t0, %lo(MOVING_CHAR)(gp)
    #write the new character
    sw t0, 0(a0)
    
MOVING_EXIT:
    lw ra, 0(sp) #restore return address
    addi sp, sp, 4 #update stack pointer
    ret
    
    nop
    nop
    nop
    
WAIT:
    lw t0, BUTTON_OFFSET(tp)
     #see if btnc is pressed (to reset game)
    li t1, BUTTON_C_MASK
    beq t1, t0, RESTART #if the center button is pressed, go back to init monkey screen
    j WAIT
    
#data segment
.data
#this location stores the value of the character
MOVING_CHAR:
    .word CHAR_MONKEY
    
#stores the value of the overwritten character
DISPLACED_CHAR:
    .word 0
    
#stores the memory address of the moving character
DISPLACED_CHAR_LOC:
    .word 0
