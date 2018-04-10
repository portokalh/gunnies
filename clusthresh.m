%p=0.05, df=15-> run randomize with ?c tinv(1-p,df)
myp=0.05
n1=12
n2=12
mydf= n1 + n2 - 2 
mycluusthresh=tinv(1-myp,mydf)
%or ?C tinv(1-p,df)