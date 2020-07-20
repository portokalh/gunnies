#https://inattentionalcoffee.wordpress.com/2017/02/14/data-in-the-raw-violin-plots/

# Library
library(ggplot2);
library(tidyr);

library(plyr);
library(dplyr);

setwd('/Users/alex/Documents/MATLAB/alex/git1/')
pathout='/Users/alex/Documents/MATLAB/alex/git1/results/'
roinames <- read.csv('./volstats4R2.csv',nrows=1,header = FALSE)
volume <- read.csv('./volstats4R3.csv',header = TRUE)
n<-nrow(volume);
# errbar_lims = group_by(volume, genotype) %>%
#   summarize(mean=mean(volume$X1), se=sd(volume$X1)/sqrt(n()),
#             upper=mean+(2*se), lower=mean-(2*se))
# mean_se_violin = ggplot() +
#   geom_violin(data=dat, aes(x=condition, y=value, fill=condition, color=condition)) +
#   geom_point(data=dat, aes(x=condition, y=value), stat="summary", fun.y=mean, fun.ymax=mean, fun.ymin=mean, size=3) +
#   geom_errorbar(aes(x=errbar_lims$condition, ymax=errbar_lims$upper,
#                     ymin=errbar_lims$lower), stat='identity', width=.25) +
#   theme_minimal()


# for (i in 4:336){
#   temp<-volume[,i];
#   temp2<-100*temp/volume$Brain;
#   volume[,i]<-temp2;
# }

# errbar_lims = group_by(volume, genotype) %>%
#   summarize(mean=mean(volume$X1), se=sd(volume$X1)/sqrt(n()),
#             upper=mean+(2*se), lower=mean-(2*se))

res<-colnames(volume)
res[res == " "] <- ""

my_i<-c(23,	17,	10,	3,	15,	9,	5,	31,	33,	11,	28,	36,	8,	13,	7,	2)

for (i in my_i) {
  print(i)
Genotype<-factor(volume$genotype)
Group<-volume$genotype
Volume<-volume[,i+1]

p<-ggplot(volume, aes(Genotype,Volume),removePanelGrid=TRUE,removePanelBorder=TRUE) +
  theme(text = element_text(size=40)) +
  geom_violin(aes(fill = Group))+
  geom_boxplot(width=0.1, fill="white", outlier.colour="black", outlier.shape=16, outlier.size=2, notch = FALSE) +
  #axisLine=c(0.5, "solid", "black") +
  stat_summary(fun.y = "mean", geom = "point", shape = 8, size = 3, color = "midnightblue") +
  geom_crossbar(stat="summary", fun.y=mean, fun.ymax=mean, fun.ymin=mean, fatten=2, width=.5) +
  #geom_errorbar(aes(x=errbar_lims$genotype, ymax=errbar_lims$upper,ymin=errbar_lims$lower), stat='identity', width=.25) +
  geom_point(color="black", size=1, position = position_jitter(w=0.1))
labs(title="Volume (% Brain )",x="Genotype", y = res[i+1])


p+labs(y="Volume (% Brain)",x="Group", title = res[i+1]) + theme_classic()+theme(text = element_text(size = 20)) 

ggsave(paste(pathout,res[i+1],"VolumePercentage.png"), width=7, height=4, dpi=200)

}



for (i in 38) {
  print(i)
  Genotype<-factor(volume$genotype)
  Group<-volume$genotype
  Volume<-volume[,i+1]
  
  p<-ggplot(volume, aes(Genotype,Volume),removePanelGrid=TRUE,removePanelBorder=TRUE) +
    theme(text = element_text(size=40)) +
    geom_violin(aes(fill = Group))+
    geom_boxplot(width=0.1, fill="white", outlier.colour="black", outlier.shape=16, outlier.size=2, notch = FALSE) +
    #axisLine=c(0.5, "solid", "black") +
    stat_summary(fun.y = "mean", geom = "point", shape = 8, size = 3, color = "midnightblue") +
    geom_crossbar(stat="summary", fun.y=mean, fun.ymax=mean, fun.ymin=mean, fatten=2, width=.5) +
    #geom_errorbar(aes(x=errbar_lims$genotype, ymax=errbar_lims$upper,ymin=errbar_lims$lower), stat='identity', width=.25) +
    geom_point(color="black", size=1, position = position_jitter(w=0.1))
  labs(title="Volume (mm3 )",x="Genotype", y = res[i+1])
  
  
  p+labs(y="Volume (mm3)",x="Group", title = res[i+1]) + theme_classic()+theme(text = element_text(size = 20)) 
  
  ggsave(paste(pathout,res[i+1],"VolumeTotal.png"), width=7, height=4, dpi=200)
  
}